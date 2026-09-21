# AUDI-HA — Home Assistant 衍生 iOS 客户端

一个基于 Home Assistant **REST + WebSocket API** 的轻量 iOS 客户端（SwiftUI）。
作为 HA 官方 App 的衍生版，聚焦最核心的诉求：**连上你自己的 HA 实例 → 看设备 → 实时控制 → 收藏常用**。

> 为什么是「衍生」：它不重新实现 Lovelace 仪表盘引擎，而是用原生 SwiftUI 重写一套简洁的设备控制界面，依赖 HA 的开放 API，可视为官方客户端的精简分支。

## 功能

- ✅ 连接自有 HA 实例（实例地址 + 长期访问令牌）
- ✅ 设备仪表盘，按 `domain` 分组（light / switch / sensor / cover …）
- ✅ 开关、灯、窗帘、风扇等实体的实时开/关控制
- ✅ WebSocket 订阅 `state_changed`，状态秒级同步刷新
- ✅ 收藏常用设备，独立「收藏」页快速操作
- ✅ 自签名 https 支持（忽略 SSL 开关）
- ✅ iOS 原生风格 UI，自动适配深色模式

## 运行方式

> 当前环境是 Linux 沙箱，没有 macOS / Xcode，**无法在此直接编译出可安装的 .ipa**。
> 请在你的 Mac 上用以下任一方式打开并运行。

### 方式 A：Xcode 新建工程（零依赖，最稳）

1. Xcode → `New Project` → iOS → `App`，Product Name 填 `AUDI_HA_iOS`，Interface: **SwiftUI**，Language: **Swift**
2. 删除模板自动生成的 `ContentView.swift`
3. 把本仓库 `AUDI_HA_iOS/` 目录下的 **所有 `.swift` 文件** 按原目录结构拖入工程对应 Group
4. 在 `Info.plist` 加入：`NSAppTransportSecurity → NSAllowsArbitraryLoads = YES`（本仓库已附带，若用模板需手动加）
5. 选模拟器或真机，▶️ Run

### 方式 B：XcodeGen（一条命令生成工程）

```bash
brew install xcodegen
cd AUDI-HA-iOS
xcodegen generate          # 读取 project.yml，生成 AUDI-HA-iOS.xcodeproj
open AUDI-HA-iOS.xcodeproj
```

## 目录结构

```
AUDI-HA-iOS/
├── project.yml                     # XcodeGen 工程定义
└── AUDI_HA_iOS/
    ├── Info.plist                 # 含 NSAppTransportSecurity 放开 http/自签
    ├── AUDI_HA_iOSApp.swift       # @main 入口
    ├── Models/
    │   ├── HAEntity.swift         # 实体模型 + 异构属性解码
    │   └── ConnectionSettings.swift
    ├── Networking/
    │   ├── HAClient.swift         # REST: 拉状态 / 调服务
    │   └── HAWebSocketController.swift  # WebSocket 实时通道
    ├── ViewModels/
    │   └── DashboardViewModel.swift     # 状态机：连接/列表/收藏/实时
    ├── Views/
    │   ├── RootView.swift         # 路由 + Tab
    │   ├── ConnectionView.swift   # 连接配置
    │   ├── DashboardView.swift    # 设备仪表盘
    │   ├── EntityRowView.swift    # 实体行
    │   ├── FavoritesView.swift    # 收藏
    │   ├── EntityDetailView.swift # 详情
    │   └── SettingsView.swift     # 设置
    └── Assets.xcassets/
```

## 架构要点

| 层 | 职责 |
|----|------|
| **Models** | `HAEntity` 用 `HAAttributeValue` 枚举兼容 HA 异构属性 JSON；时间戳兼容微秒 |
| **Networking** | `HAClient`（actor，async/await）封装 REST；`HAWebSocketController` 走 `auth → subscribe_events` 协议 |
| **ViewModels** | `DashboardViewModel`（`@MainActor`）持有实体列表、收藏、连接态，WS 回调在主线程合并 |
| **Views** | SwiftUI 声明式 UI，可开关实体直接渲染 `Toggle`，其余进详情页 |

## 如何连接你的实例

1. HA 网页端 → 左下角用户头像 → **长期访问令牌** → 创建令牌，复制字符串
2. App 首次打开进入「连接设置」：填实例地址（如 `http://192.168.1.10:8123` 或 `https://ha.xxx.com`）+ 令牌
3. 若是自签 https，打开「忽略 SSL 证书错误」
4. 保存后会先验证连通性，再进入仪表盘

## 安全提示

⚠️ 本 demo 为方便演示，使用 `UserDefaults` **明文**保存访问令牌。
生产环境请改为 **Keychain** 存储（可引入 `KeychainAccess` 或系统 `SecItem` API）。

## 后续可扩展方向

- 渲染 HA 的 `lovelace` 视图 / 区域（area）
- 设备追踪地图（device_tracker）
- iOS Widget / 快捷指令控制
- 推送通知（HA `notify` + APNs）
- 多实例切换

---
*衍生自 Home Assistant 开放 API。Home Assistant 相关商标归其各自所有者。*
