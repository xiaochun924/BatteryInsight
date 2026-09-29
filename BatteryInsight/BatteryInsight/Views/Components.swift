import SwiftUI

// MARK: - 中文日期

/// 日期一律用中文格式显示（如「9月23日」）。
///
/// 为什么不用 `.formatted(.dateTime.month().day())`：那会跟随设备语言/地区，
/// 英文环境下渲染成 "Sep 23"，与中文界面不一致。这里固定 zh_CN 本地化。
extension Date {
    // iOS 26 SDK：DateFormatter 已标注 Sendable，static let 常量无需
    // `nonisolated(unsafe)`（实例只读不改配置，跨线程使用安全）。
    private static let cnMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    private static let cnFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    /// 「9月23日」
    var chineseDateText: String { Date.cnMonthDay.string(from: self) }
    /// 「2026年9月23日 08:00」
    var chineseDateTimeText: String { Date.cnFull.string(from: self) }
}

// MARK: - 右滑返回（隐藏导航栏后恢复系统手势）

extension View {
    /// 隐藏系统导航栏后恢复右滑返回。
    /// 原实现复制在 TrendDetail / RecordDetail / LifetimePrediction / BatteryReport
    /// 四个页面（含 UsageDetailSheet）里，统一抽成组件；
    /// 用 simultaneousGesture 避免与顶栏按钮的点击手势竞争。
    func swipeToDismiss(_ dismiss: DismissAction) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    if value.translation.width > 60,
                       abs(value.translation.width) > abs(value.translation.height) {
                        dismiss()
                    }
                }
        )
    }
}

// MARK: - 统一卡片容器（H-2：消除各页卡片样式的重复实现）

/// 统一的圆角卡片容器：内边距 + 材质/渐变底 + 可选描边，圆角 16 continuous。
///
/// 用途：LifetimePredictionView 等以「常规材质底」为主的卡片统一走它；
/// 需要渐变卡底的页面（趋势分析页淡绿渐变，用户确认过的视觉）也通过
/// `fillStyle` 传入 LinearGradient，保持全局一致的圆角与内边距。
/// 有专属形态的卡片（主页记录卡 ultraThinMaterial 14pt + 描边、详情页指标格
/// 按色彩底）保留各自样式，不强行套用。
struct CardContainer<Content: View>: View {
    /// 圆角（默认 16，与全项目卡片一致）
    var cornerRadius: CGFloat = 16
    /// 底色：材质 / 渐变 / 纯色均可
    var fillStyle: AnyShapeStyle = AnyShapeStyle(.regularMaterial)
    /// 可选细描边（传 .separator.opacity(...) 之类）
    var stroke: Color?
    /// 内容四周内边距
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fillStyle,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if let stroke {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                }
            }
    }
}
