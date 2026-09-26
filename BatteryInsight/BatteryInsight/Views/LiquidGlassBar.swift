import SwiftUI

// MARK: - 液态玻璃动作按钮底

/// 全 App 顶栏已改用 **iOS 26 官方液态玻璃导航栏**
/// （`.toolbarBackgroundVisibility(.visible, for: .navigationBar)`——可见背景即由系统
/// 渲染为液态玻璃材质），
/// 标题、返回按钮、滚动收成胶囊均为官方套件。
/// 本文件只保留顶栏动作按钮（菜单 / 分享 / 关闭 / 对勾）的玻璃圆底与胶囊底扩展。

extension View {
    /// 液态玻璃胶囊底（顶栏动作按钮通用）：iOS 26 官方 `.glassEffect()` + 提亮。
    /// 用法：`Text("分析").padding(...).glassCapsuleBackground()`
    func glassCapsuleBackground() -> some View {
        self.background {
            Capsule()
                .glassEffect()
                .brightness(0.12)
        }
    }

    /// 液态玻璃圆形底（顶栏圆形按钮通用）：iOS 26 官方 `.glassEffect()` + 提亮。
    func glassCircleBackground() -> some View {
        self.background {
            Circle()
                .glassEffect()
                .brightness(0.12)
        }
    }
}
