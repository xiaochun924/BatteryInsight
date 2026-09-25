import SwiftUI

// MARK: - 液态玻璃悬浮顶栏

/// 全 App 统一的「液态玻璃悬浮顶栏」样式组件。
///
/// 设计要点（对齐全局 iOS 界面偏好）：
/// - 完全隐藏系统导航栏（`.toolbar(.hidden, for: .navigationBar)`），
///   顶部只留下真正的内容，不给系统导航栏留空间。
/// - 左上角圆形玻璃返回按钮（仅非根页面 / 可关闭页面显示）。
/// - 中间悬浮玻璃胶囊标题：**恒定居中**——用 ZStack 把标题放在整行正中，
///   左右两侧按钮宽度不一致也不会把标题挤偏。
/// - 纯透明背景，**不加白色蒙皮 / 磨砂遮挡层**——让内容直接浮在玻璃上。
///
/// 用法：`.liquidGlassTopBar(title: "电池健康", leading: { … }, trailing: { … })`
struct LiquidGlassTopBar: ViewModifier {
    /// 居中胶囊标题文案
    let title: String
    /// 是否显示左上角圆形玻璃返回按钮（默认 true）
    var showsBackButton = true
    /// 返回/关闭动作；不传则使用 dismiss
    var backAction: (@MainActor () -> Void)? = nil
    /// 顶栏左侧额外内容（放在返回按钮右侧的槽位）
    var leading: (@MainActor () -> AnyView)? = nil
    /// 顶栏右侧内容槽位
    var trailing: (@MainActor () -> AnyView)? = nil

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            // 完全隐藏系统导航栏
            .toolbar(.hidden, for: .navigationBar)
            // 顶部留出悬浮栏高度：顶栏胶囊约占「状态栏 + 40pt」，
            // 内容从胶囊下方开始（48pt），避免页面内容与悬浮顶栏互相遮挡
            .safeAreaPadding(.top, 48)
            .overlay(alignment: .top) { bar }
    }

    @ViewBuilder
    private var bar: some View {
        ZStack {
            // 中间悬浮玻璃胶囊标题：ZStack 默认居中，标题始终在整行正中，
            // 不参与左右 HStack 的宽度分配，左右按钮再宽也不会把它挤偏。
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .allowsHitTesting(false)

            // 左侧组合：返回按钮 + 自定义槽位（如主页面左上角菜单），靠左对齐
            HStack(spacing: 10) {
                if showsBackButton {
                    glassButton(systemName: "chevron.left") {
                        (backAction ?? { dismiss() })()
                    }
                    .accessibilityLabel("返回")
                }
                if let leading {
                    leading()
                }
                Spacer(minLength: 0)
            }

            // 右侧自定义槽位，靠右对齐
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if let trailing {
                    trailing()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    /// 圆形玻璃按钮（返回按钮统一走这里）
    private func glassButton(systemName: String,
                             action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View 扩展

extension View {
    /// 应用液态玻璃悬浮顶栏。`showsBackButton` 决定是否显示左上角返回按钮；
    /// `leading` / `trailing` 放置顶栏两侧的动作按钮（各传一个视图，如 Menu / HStack）。
    /// 闭包内通过 AnyView 桥接后存储，规避 `some View` 不能作存储属性的限制。
    func liquidGlassTopBar(
        title: String,
        showsBackButton: Bool = true,
        backAction: (@MainActor () -> Void)? = nil,
        leading: @escaping @MainActor () -> some View = { EmptyView() },
        trailing: @escaping @MainActor () -> some View = { EmptyView() }
    ) -> some View {
        modifier(
            LiquidGlassTopBar(
                title: title,
                showsBackButton: showsBackButton,
                backAction: backAction,
                leading: { AnyView(leading()) },
                trailing: { AnyView(trailing()) }
            )
        )
    }
}
