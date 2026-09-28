import SwiftUI

// MARK: - 液态玻璃悬浮顶栏（参考 home-inventory 的官方 Liquid Glass 实现）

/// 全局统一顶栏规范：纯透明导航栏；左上角圆形玻璃按钮；
/// 中间悬浮玻璃胶囊标题；完全隐藏系统导航栏；不加白色蒙皮 / 磨砂遮挡。
/// 全部使用 iOS 26 官方 Liquid Glass 套件：
/// - `GlassEffectContainer`：让左右按钮与中间胶囊共享玻璃采样区，效果一致
/// - `.glassEffect(.clear, in: .capsule)`：胶囊标题
/// - `.glassEffect(.thin.interactive(), in: .circle)`：可交互圆形按钮
///   用 thin 而非 regular：真机滚动时 regular 档玻璃对下方内容持续采样，
///   多页面滑动掉帧；thin 采样成本更低，圆形按钮（透明为主）观感几乎无差
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
                // 中间悬浮玻璃胶囊标题（官方 Liquid Glass）。
                // 用系统样式 .headline 而非固定 .system(size:16)：
                // 随 Dynamic Type 缩放，VoiceOver 大字模式下不截断
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
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
    /// 无障碍标签；nil 时按图标名映射中文（VoiceOver 朗读，纯图标按钮必须可读）
    var label: String?
    let action: () -> Void

    init(icon: String,
         tint: Color = .primary,
         size: CGFloat = 40,
         label: String? = nil,
         action: @escaping () -> Void) {
        self.icon = icon
        self.tint = tint
        self.size = size
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: size, height: size)
                .glassEffect(.thin.interactive(), in: .circle)
                // iOS 26 按钮可点击区域默认只覆盖内容（图标本身），
                // contentShape 让整个圆形玻璃底都可点
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver：纯图标按钮必须有可读标签；未显式指定时按常用图标映射中文
        .accessibilityLabel(label ?? Self.defaultLabel(for: icon))
    }

    /// 项目内常用图标的无障碍名称映射（VoiceOver 朗读用）
    private static func defaultLabel(for icon: String) -> String {
        switch icon {
        case "chevron.left": return "返回"
        case "gearshape": return "设置"
        case "xmark": return "关闭"
        case "checkmark": return "确认"
        case "square.and.arrow.up": return "分享"
        default: return icon
        }
    }
}
