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

## 📥 从系统「分析数据」导入<｜hy_place▁holder▁no▁813｜>

这才是拿到**真实**健康度、循环次数、实际容量 / 出厂容量的正确姿势。

**步骤**：设置 → 隐私与安全性 → 分析与改进 → 分析数据 → 找到 `Analytics-*.ips`（按日期排序选最新）→ 全选复制 → 回到 App「日志」页右上角导入 → 粘贴 → 解析并导入。

> ⚠️ **为什么不能自动读取**：该目录在系统进程命名空间下，第三方 App 无权限访问，这也是合规 App 的普遍做法（手动导入）。

App 会从 `batteryhealth` 段落解析这些**原生字段**：

| 日志字段 | 含义 |
|---------|------|
| `MaximumCapacityPercent` | 系统健康度 % |
| `CycleCount` | 循环次数 |
| `NominalChargeCapacity` | 当前实际容量 mAh |
| `DesignCapacity` | 出厂（设计）容量 mAh |
| `Voltage` / `Temperature` | 电压 V / 温度 ℃ |

界面刻意分成两个区块：

1. **系统原生数据** —— iOS 直接写入，未经任何推算，可信度高
2. **衍生分析指标** —— 由原生字段计算，同时给出**计算口径与依据**，例如：
   - 计算健康度 = 实际容量 ÷ 出厂容量 × 100%（出现 101.72% 属正常，电芯有正公差）
   - 容量余量、单位循环容量
   - 健康度变化 %/月、每循环衰减 mAh/次、预计可用至 80% 还剩多少循环

**关于「衰减稳定性 / 电芯一致性」**：不少第三方工具会给出这两项，但其口径依赖日志中更多未公开字段（`AppleRawMaxCapacity`、`Qmax`、`WeightedRa`），仅凭出厂容量与实际容量**无法唯一确定**。强行拟合只会得到看似合理却无依据的数字，因此本 App 不做这两项——页面里有折叠说明。

导入多条不同日期的日志后，会自动画出容量趋势曲线。

## 功能

- **耗电速率**：按 %/小时 估算当前掉电速度，并预估剩余可用时长
- **电量趋势**：Swift Charts 折线图，24 小时 / 7 天 / 全部切换，充电段与放电段分色
- **充电会话分析**：自动记录每次充电的起止、时长、充入电量、充电速度，识别「整夜充电」
- **健康度追踪**：手动录入最大容量，画衰减曲线，算 %/月 衰减速率，预估降到 80% 还需几个月
- **优化建议**：基于真实数据生成（整夜充电、满电久插、深度放电、健康度阈值、耗电过快等）
- **分析日志导入**：粘贴 Analytics-*.ips，字段驱动的宽松解析（对截断/拼接/多条目都容错），原生数据与衍生指标分块展示

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
    │   ├── AnalyticsLogParser.swift# 分析日志解析（字段驱动的宽松扫描）
    │   └── DerivedMetrics.swift    # 衍生指标计算（含公式与依据）
    ├── ViewModels/
    │   └── BatteryViewModel.swift  # 状态机（@MainActor）
    └── Views/
        ├── RootTabView.swift       # Tab 容器
        ├── DashboardView.swift     # 概览：电量环 + 指标卡
        ├── TrendsView.swift        # 趋势：Charts 曲线
        ├── ChargingView.swift      # 充电：会话统计 + 列表
        ├── HealthView.swift        # 健康：录入 + 衰减曲线
        ├── AnalyticsView.swift     # 日志：粘贴导入 + 原生/衍生分块
        └── TipsView.swift          # 建议列表
```

## 架构要点

- **`BatteryMonitor`**（`@MainActor`）：开启 `isBatteryMonitoringEnabled`，60 秒定时采样 + 监听 `batteryLevelDidChange` / `batteryStateDidChange` 通知；状态翻转时回调，用于开启/结算充电会话
- **`DataStore`**：采样、会话、健康度三类数据落 UserDefaults；采样上限 20000 条，超出丢弃最旧
- **`BatteryAnalytics`**：纯函数分析，无副作用，便于单测
- **`BatteryViewModel`**（`@MainActor`）：串联三者，对外暴露 `@Published`

## 数据说明

- **全部数据仅存本机**，不联网、不上传、无第三方 SDK
- demo 用 `UserDefaults` 存储；生产建议换 **SwiftData / CoreData**，采样量会持续增长
- 「概览」页可一键清空全部数据

## 后续可扩展

- 用 **SwiftData** 替换 UserDefaults，支持更大数据量与查询
- 加 **Widget / 锁屏小组件**展示当前电量与耗电速率
- 充电完成、低电量时发**本地通知**提醒拔电
- 结合 **Shortcuts** 在特定场景自动打点采样
- 导出 CSV 做长期分析

---
*本 App 仅使用 Apple 公开 API，未调用任何私有接口。*
