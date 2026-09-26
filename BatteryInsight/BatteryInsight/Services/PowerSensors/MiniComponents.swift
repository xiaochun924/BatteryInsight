import SwiftUI

// MARK: - MiniWatts 风格组件（发热页移植用）

/// 带标题的卡片面板。发热页的每个区块都放在一个 Panel 里。
struct Panel<Content: View>: View {
    var title: LocalizedStringResource?
    var systemImage: String?
    /// 右侧小字（copy 用 `Text("…")`，实测数值用 `Text(verbatim:)`）
    var trailing: Text?
    @ViewBuilder var content: () -> Content

    init(_ title: LocalizedStringResource? = nil,
         systemImage: String? = nil,
         trailing: Text? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || trailing != nil {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.mwMuted)
                    }
                    if let title {
                        Text(title).mwCaption()
                    }
                    Spacer(minLength: 8)
                    if let trailing {
                        trailing
                            .mwMono(size: 11)
                            .foregroundStyle(Color.mwMuted)
                    }
                }
            }
            content()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.mwCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.mwCardStroke, lineWidth: 1)
        )
    }
}

/// 说明小字：图标 + 文本。
struct EmptyNote: View {
    let text: LocalizedStringResource
    var systemImage: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.mwMuted)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.mwMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 标签 + 数值 + 单位 + 来源说明。面板里指标列的通用组件。
struct Metric: View {
    let caption: LocalizedStringResource
    let value: String
    var unit: String?
    var tint: Color = .primary
    /// 数值来源说明（copy 或硬件名 `Text(verbatim:)`）
    var footnote: Text?
    var size: CGFloat = 24

    /// "—" 表示探针没有返回读数，按「缺失」而非读数渲染
    private var isPlaceholder: Bool { value == "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption).mwCaption()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .mwReadout(size: isPlaceholder ? size * 0.7 : size)
                    .foregroundStyle(isPlaceholder ? Color.mwMuted.opacity(0.55) : tint)
                if let unit {
                    Text(unit)
                        .font(.system(size: size * 0.48, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.mwMuted)
                }
            }
            if let footnote {
                footnote
                    .font(.caption2)
                    .foregroundStyle(Color.mwMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 小状态胶囊：充电状态、热状态、无线徽标等。
struct Pill: View {
    let text: Text
    var systemImage: String?
    var tint: Color = .mwMuted

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            }
            text
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.5))
    }
}

/// 标签横向条，用于温度分区与适配器利用率。
struct BarRow: View {
    let title: Text
    /// 恒为格式化测量值——"42.8 °C"、"80%"——不做本地化
    let detail: String
    /// 0…1
    let fraction: Double
    let tint: Color
    var subtitle: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let subtitle {
                        subtitle
                            .mwMono(size: 10)
                            .foregroundStyle(Color.mwMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(detail)
                    .mwReadout(size: 14, weight: .semibold)
                    .foregroundStyle(tint)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.mwMuted.opacity(0.15))
                    Capsule()
                        .fill(Theme.gradient(tint))
                        .frame(width: max(3, geometry.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 5)
        }
    }
}
