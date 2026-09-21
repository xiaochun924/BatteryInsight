# workbuddy

iOS 项目集合，包含两个 SwiftUI 应用。每次推送到 `main` 会自动触发 GitHub Actions 在 macOS 环境下编译验证。

| 项目 | 说明 | 部署目标 |
|------|------|---------|
| [`HA-iOS`](./HA-iOS) | 基于 Home Assistant 的智能家居客户端：连接 HA 实例、设备仪表盘、WebSocket 实时状态、收藏。**iOS 26 液态玻璃 + Swift 6** | iOS 26.0+ |
| [`BatteryInsight`](./BatteryInsight) | iPhone 电池效率分析：耗电速率、充电会话、健康度衰减追踪、省电建议 | iOS 16.0+ |

## 编译状态

`iOS Build` workflow 会对两个工程分别执行 `xcodegen generate` + `xcodebuild`（模拟器 SDK，不签名）。

## 本地构建

两个工程都用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理工程定义（`project.yml`），不需要手工维护 `.xcodeproj`。

```bash
# 方式一：XcodeGen（推荐）
brew install xcodegen
cd HA-iOS && xcodegen generate && open HA-iOS.xcodeproj

# 方式二：直接用 Xcode 模板
# 新建 iOS App 模板 → 删除 ContentView.swift → 把 <项目>/<项目>/ 下的 .swift 按目录拖入 → Run
```

`BatteryInsight` 同样流程，工程目录为 `BatteryInsight`。

## 说明

- 两个工程均为**源码工程**，需要 macOS + Xcode 才能编译出可安装的 App。
- `BatteryInsight` 受 iOS 平台限制：第三方 App 无法读取系统「电池健康/最大容量/循环次数」（私有 API，上架会被拒），因此健康度由用户手动录入，电量与充电状态通过 `UIDevice` 合法读取。
- CI 使用模拟器 SDK 且关闭签名，产物为 `.app`，不含签名，无法直接安装到真机。

## 许可证

[MIT](./LICENSE)
