import SwiftUI

// MARK: - 中文日期

/// 日期一律用中文格式显示（如「9月23日」）。
///
/// 为什么不用 `.formatted(.dateTime.month().day())`：那会跟随设备语言/地区，
/// 英文环境下渲染成 "Sep 23"，与中文界面不一致。这里固定 zh_CN 本地化。
extension Date {
    // Swift 6：DateFormatter 非 Sendable，作为共享静态缓存需显式 `nonisolated(unsafe)`。
    // DateFormatter 内部通过锁保证线程安全；这些实例只读不改配置，跨线程使用是安全的。
    nonisolated(unsafe) private static let cnMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    nonisolated(unsafe) private static let cnFull: DateFormatter = {
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

/// 指标卡片。原先定义在 DashboardView 里，随概览页一起删除会连带弄丢，
/// 故抽到独立文件供健康 / 趋势复用。
struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title2.bold())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 带图标的说明卡片
struct HintCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            content
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
