import SwiftUI

// MARK: - 液态玻璃悬浮顶栏（参考 home-inventory 的官方 Liquid Glass 实现）

/// 全局统一顶栏规范：纯透明导航栏；左上角圆形玻璃按钮；
/// 中间悬浮玻璃胶囊标题；完全隐藏系统导航栏；不加白色蒙皮 / 磨砂遮挡。
/// 全部使用 iOS 26 官方 Liquid Glass 套件：
/// - `GlassEffectContainer`：让左右按钮与中间胶囊共享玻璃采样区，效果一致
/// - `.glassEffect(.clear, in: .capsule)`：胶囊标题
/// - `.glassEffect(.regular.interactive(), in: .circle)`：可交互圆形按钮
struct GlassTopBar<Leading: View, Trailing: View>: View {
    let title: String
    /// 水平内边距：全屏页 16；sheet 弹出页加大到 28，避开 iOS 26 sheet 顶部大圆角
    var horizontalPadding: CGFloat = 16
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(title: String,
         horizontalPadding: CGFloat = 16,
         @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.horizontalPadding = horizontalPadding
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        // 玻璃容器：左右圆形按钮与中间胶囊标题共享玻璃采样区，效果更一致
        GlassEffectContainer {
            // 标题用 ZStack 绝对居中，不受左右按钮宽度影响；左右按钮覆盖在两侧
            ZStack {
                // 中间悬浮玻璃胶囊标题（官方 Liquid Glass）
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .glassEffect(.clear, in: .capsule)

                HStack {
                    leading()
                    Spacer()
                    trailing()
                }
            }
        }
        .frame(height: 48)
        .padding(.horizontal, horizontalPadding)
    }
}

/// 圆形玻璃按钮（官方 Liquid Glass，可交互）
struct GlassCircleButton: View {
    let icon: String
    var tint: Color = .primary
    var size: CGFloat = 40
    let action: () -> Void

    init(icon: String, tint: Color = .primary, size: CGFloat = 40, action: @escaping () -> Void) {
        self.icon = icon
        self.tint = tint
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
                // iOS 26 按钮可点击区域默认只覆盖内容（图标本身），
                // contentShape 让整个圆形玻璃底都可点
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 旧扩展（兼容保留：玻璃圆底 / 胶囊底）

extension View {
    /// 液态玻璃胶囊底（顶栏动作按钮通用）：iOS 26 官方 `.glassEffect()` + 提亮。
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
