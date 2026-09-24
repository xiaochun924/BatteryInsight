# BatteryInsight — iPhone 电池效率分析

一个用 SwiftUI 写的 iPhone 电池分析 App：**采样电量 → 分析耗电与充电 → 追踪健康度衰减 → 给出保养建议**。

## ⚠️ 先说清楚 iOS 的平台限制

这一点决定了这个 App 能做什么、不能做什么：

| 数据 | 能否获取 | 说明 |
|------|---------|------|
| 当前电量 | ✅ 可以 | `UIDevice.batteryLevel`（0.0~1.0） |
| 充电状态 | ✅ 可以 | `UIDevice.batteryState`（未充电/充电中/已充满） |
| **最大容量 %** | ⚠️ 手动导入 | 属私有 API，不可用 → **由你从系统分析日志导入**（见下） |
| **循环次数** | ⚠️ 手动导入 | 同上 → **从同一份日志一并解析出来** |
| 各 App 耗电明细 | ❌ 不行 | 系统未开放给第三方 |

另外：**iOS 会把后台 App 挂起**，定时采样与系统通知在后台都会暂停。
所以采样只在**前台**持续有效，长时间不开 App 的时段没有数据，这是系统行为而非 Bug。

> 结论：电量/充电状态自动采集，健康度与循环次数从系统分析日志导入（或手动录入），分析基于这两类数据。

## 📥 从系统「分析数据」导入

这才是拿到**真实**健康度、循环次数、实际容量 / 出厂容量的正确姿势。

### 方式一：从文件导入（推荐）

1. 设置 → 隐私与安全性 → 分析与改进 → 分析数据 → 找到 `Analytics-*.ips`（按日期排序选最新）
2. 点开文件 → 右上角**分享** → **存储到「文件」**（选个位置存下；多存几个不同日期的，趋势图才有意义）
3. 回到 App「日志分析」页 → 右上角导入 → **选择日志文件** → 选中刚存的文件

支持**一次选多个**批量导入，也可以从隔空投送、iCloud 云盘里选。

### 方式二：粘贴文本

不方便存文件时用：在「分析数据」里打开 `Analytics-*.ips` → 全选 → 拷贝 → 回到 App → 导入 → **粘贴文本**（App 内还有「从剪贴板填入」按钮）。只需含 `batteryhealth` 字段的片段即可。

> ⚠️ **为什么不能自动读取**：该目录在系统进程命名空间下，第三方 App 无权限访问，这也是合规 App 的普遍做法（手动导入）。文件导入走的是系统文档选择器，由你显式授权后读取，本质仍是「你给 App 什么，它读什么」。

> 🔧 **为什么不用 SwiftUI 的 `.fileImporter`**：它在**真机 iPhone** 上有已知问题——选择器能打开、文件也列得出来，但点了文件既选不中、面板也不关闭，回调永不触发（模拟器 / iPad / Mac Catalyst 正常）。因此改用 `UIViewControllerRepresentable` 包一层 UIKit 的 `UIDocumentPickerViewController`，见 `Views/DocumentPicker.swift`。

> 💡 `.ips` 没有公开 UTI，因此文档选择器的允许类型里包含了 `public.data` 兜底，否则这些文件在选择器里会是灰色不可选的。

导入结果会如实汇报：读取了几个文件、解析出几条记录、新增几条、哪些重复被跳过、哪些文件没解析出数据。

## 🔍 解析方式：结构优先，正则兜底

`.ips` 的真实结构是「一行元数据头 + 一行 JSON 正文」，电池快照在正文的 `batteryhealth` 对象里：

```
{"timestamp":"2026-09-19 10:23:45.6780 +0800","bug_type":"115",...}
{"batteryhealth":{"CycleCount":123,"DesignCapacity":4823,
  "MaximumCapacityPercent":100,"NominalChargeCapacity":4906,...},"osVersion":...}
```

所以解析**按结构走**，而不是靠正则在全文里扫数字：

1. 按花括号配平切出顶层 JSON 对象（正确处理字符串内的 `{}` 与转义）
2. `JSONSerialization` 解析 → 递归定位 `batteryhealth`（兼容大小写与命名差异）
3. 按类型取值；正文没有时间戳时，取它之前最近一个带 `timestamp` 的对象
4. 只有在 JSON 解析失败（日志被截断、只复制了片段）时才退回字段扫描

这样字段归属明确，不会串值，也不用猜哪个数字属于哪个键。

App 从 `batteryhealth` 解析这些**原生字段**：

| 日志字段 | 含义 |
|---------|------|
| `MaximumCapacityPercent` | 系统健康度 % |
| `CycleCount` | 循环次数 |
| `NominalChargeCapacity` | 当前实际容量 mAh |
| `DesignCapacity` | 出厂（设计）容量 mAh |
| `Voltage` / `Temperature` | 电压 V / 温度 ℃ |

除此之外，`batteryhealth` 里**其余数值字段**（如 `AppleRawMaxCapacity`、`AppleRawNominalCapacity`、`Qmax`、`WeightedRa`、`PresentDOD` 等）也会照原样收录并展示——不同机型写入的字段集合本就不同，系统写什么就存什么。但这些字段苹果未公开含义，因此只呈现键名与数值，**不做任何解读**。

界面刻意分成两个区块：

1. **系统原生数据** —— iOS 直接写入，未经任何推算，可信度高
2. **衍生分析指标** —— 由原生字段计算，同时给出**计算口径与依据**，例如：
   - 计算健康度 = 实际容量 ÷ 出厂容量 × 100%（出现 101.72% 属正常，电芯有正公差）
   - 容量余量、单位循环容量
   - 健康度变化 %/月、每循环衰减 mAh/次、预计可用至 80% 还剩多少循环

**关于「衰减稳定性 / 电芯一致性」**：不少第三方工具会给出这两项，但其口径依赖日志中更多未公开字段（`AppleRawMaxCapacity`、`Qmax`、`WeightedRa`），仅凭出厂容量与实际容量**无法唯一确定**。强行拟合只会得到看似合理却无依据的数字，因此本 App 不做这两项——页面里有折叠说明。

导入多条不同日期的日志后，会自动画出容量趋势曲线。

## 功能

> 界面只有**一页**：电池健康（含电量趋势），一屏滚动看完。「概览」「充电」两个页面已移除——前者是实时电量指标、与健康度无关，后者依赖前台捕捉充电状态翻转，iOS 一挂起就漏记，数据不完整。

- **电量趋势**：Swift Charts 折线图，24 小时 / 7 天 / 全部切换，充电段与放电段分色
- **健康度追踪**：手动录入或从系统日志导入最大容量，画衰减曲线（含 80% 更换阈值参考线），算 %/月 衰减速率，预估降到 80% 还需几个月
- **优化建议**：基于真实数据生成（整夜充电、满电久插、深度放电、健康度阈值、耗电过快等）
- **分析日志导入**：支持**从「文件」选 .ips 批量导入**或粘贴文本；按 `batteryhealth` 结构解析（JSON 优先、正则兜底），原生数据与衍生指标分块展示

## 运行方式

> 当前环境是 Linux 沙箱，没有 macOS / Xcode，**无法在此编译出 .ipa**。请在 Mac 上运行。

### 方式 A：Xcode 新建工程（零依赖，最稳）

1. Xcode → `New Project` → iOS → `App`，Product Name 填 `BatteryInsight`，Interface: **SwiftUI**，Language: **Swift**
2. 删除模板生成的 `ContentView.swift`
3. 把 `BatteryInsight/` 目录下所有 `.swift` 文件按原目录结构拖入工程
4. 选**真机**（模拟器读不到电量，会显示"不可用"），▶️ Run

### 方式 B：XcodeGen

```bash
brew install xcodegen
cd BatteryInsight
xcodegen generate
open BatteryInsight.xcodeproj
```

### 在模拟器上跑？

模拟器不提供电池数据（电量返回 `-1`）。App 内置了 **「载入演示数据」** 按钮，点一下会生成近 7 天的模拟采样、5 次充电记录和 6 条健康度记录，所有图表立刻可看。

## 目录结构

```
BatteryInsight/
├── project.yml
└── BatteryInsight/
    ├── Info.plist
    ├── BatteryInsightApp.swift     # @main 入口
    ├── Models/
    │   ├── BatterySample.swift     # 采样点 + 状态枚举（Codable 映射 UIDevice.BatteryState）
    │   ├── ChargingSession.swift   # 充电会话（时长/速度/整夜判定）
    │   ├── HealthRecord.swift      # 健康度记录（手动录入）
    │   └── AnalyticsRecord.swift   # 分析日志解析出的一次快照
    ├── Services/
    │   ├── BatteryMonitor.swift    # UIDevice 封装：定时采样 + 状态变化通知
    │   ├── DataStore.swift         # 本地持久化 + 演示数据生成
    │   ├── BatteryAnalytics.swift  # 分析引擎 + 建议规则
    │   ├── AnalyticsLogParser.swift# 分析日志解析（按 batteryhealth 结构，正则兜底）
    │   ├── AnalyticsFileImporter.swift # 文件读取：安全作用域 + 编码兜底 + 体积上限
    │   └── DerivedMetrics.swift    # 衍生指标计算（含公式与依据）
    ├── ViewModels/
    │   └── BatteryViewModel.swift  # 状态机（@MainActor）+ 导入汇总报告
    └── Views/
        ├── RootView.swift          # 根视图（NavigationStack，单页无需 Tab）
        ├── BatteryHomeView.swift   # 主页面：健康统计 + 衰减曲线 + 电量趋势
        ├── DocumentPicker.swift    # UIKit 文档选择器（替代 .fileImporter）
        ├── Components.swift        # MetricCard / HintCard
        ├── AnalyticsView.swift     # 日志：文件/粘贴导入 + 原生/衍生分块
        └── TipsView.swift          # 建议列表
```

## 架构要点

- **`BatteryMonitor`**（`@MainActor`）：开启 `isBatteryMonitoringEnabled`，60 秒定时采样 + 监听 `batteryLevelDidChange` / `batteryStateDidChange` 通知；状态翻转时回调，用于开启/结算充电会话
- **`DataStore`**：采样、会话、健康度三类数据落 UserDefaults；采样上限 20000 条，超出丢弃最旧
- **`BatteryAnalytics`**：纯函数分析，无副作用，便于单测
- **`BatteryViewModel`**（`@MainActor`）：串联三者，对外暴露 `@Published`；导入结果用 `AnalyticsImportReport` 结构化回传
- **`AnalyticsFileImporter`**：文档选择器返回的 URL 带安全作用域，读取前后需 `start/stopAccessingSecurityScopedResource()`；单文件读取失败不中断批量导入，原因逐条记入报告

## 数据说明

- **全部数据仅存本机**，不联网、不上传、无第三方 SDK
- demo 用 `UserDefaults` 存储；生产建议换 **SwiftData / CoreData**，采样量会持续增长
- 右上角 ⋯ 菜单里可载入演示数据、一键清空全部数据

## 后续可扩展

- 用 **SwiftData** 替换 UserDefaults，支持更大数据量与查询
- 加 **Widget / 锁屏小组件**展示当前电量与耗电速率
- 充电完成、低电量时发**本地通知**提醒拔电
- 结合 **Shortcuts** 在特定场景自动打点采样
- 注册文档类型，让 `.ips` 文件能直接**分享到本 App**（省去先存「文件」这一步）
- 导出 CSV 做长期分析

---
*本 App 仅使用 Apple 公开 API，未调用任何私有接口。*
