import SwiftUI
import Charts

/// 健康趋势详情页：全屏折线图 + 底部胶囊指标，图表本身不含刻度文字。
///
/// 数据：手动记录（HealthRecord）的 systemHealthPercent / maximumCapacity。
/// 只展示真实数据，没有记录的日子不画点。
/// 视觉：纯白底 + 绿色加粗折线 + 数据点 + 胶囊数值；趋势分析页背景为淡绿渐变卡底。
struct TrendDetailView: View {
    @EnvironmentObject private var vm: BatteryViewModel
    @Environment(\.dismiss) private var dismiss

    /// 最近 7 次记录（去重到天，升序）
    private var records: [HealthRecord] {
        let calendar = Calendar.current
        var seen = Set<Date>()
        let unique = vm.healthRecords
            .sorted { $0.date > $1.date }
            .filter { seen.insert(calendar.startOfDay(for: $0.date)).inserted }
        return Array(unique.prefix(7)).reversed()
    }

    private var capacityValues: [Double?] {
        records.map { recordHealth($0) }
    }

    private var minCapacity: Double {
        let vals = capacityValues.compactMap { $0 }
        guard let min = vals.min(), let max = vals.max() else { return 0 }
        let span = max(max - min, 1)
        return max(0, min - span * 0.5)
    }

    private var maxCapacity: Double {
        let vals = capacityValues.compactMap { $0 }
        guard let min = vals.min(), let max = vals.max() else { return 100 }
        let span = max(max - min, 1)
        return min(100, max + span * 0.5)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if records.isEmpty {
                    emptyState
                } else {
                    chartCard
                    metricsRow
                }
            }
            .padding(16)
        }
        // 液态玻璃悬浮顶栏（参考 home-inventory 官方 Liquid Glass 实现）；二级页左上返回
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassTopBar(title: "健康趋势",
                        leading: { GlassCircleButton(icon: "chevron.left") { dismiss() } })
        }
        // 系统导航栏已隐藏，手动恢复右滑返回手势（统一组件，见 Components.swift）
        .swipeToDismiss(dismiss)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无趋势数据")
                .font(.headline)
            Text("先在主页导入电池分析日志，
这里会显示最近 7 次的健康度变化。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近 \(records.count) 次健康度")
                    .font(.headline)
                Spacer()
                Text("绿色折线")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    if let value = capacityValues[index] {
                        LineMark(
                            x: .value("次序", index),
                            y: .value("健康度", value)
                        )
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.monotone)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: minCapacity...maxCapacity)
            .frame(height: 200)
            // 胶囊数值：iOS 26 真机上 ScrollView 内 Charts 的 .annotation 不渲染，
            // 改用手动覆盖：GeometryReader 解析 plotFrame 后绝对定位胶囊。
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        let plot = geometry[frame]
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            if let value = capacityValues[index] {
                                capsuleLabel(value, at: index, in: plot)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.green.opacity(0.08), .white],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    /// 图表内的绿色胶囊数值标签
    private func capsuleLabel(_ value: Double, at index: Int, in plot: CGRect) -> some View {
        let total = records.count
        let x: CGFloat
        if total == 1 {
            x = plot.minX + plot.width / 2
        } else {
            x = plot.minX + plot.width * CGFloat(index) / CGFloat(total - 1)
        }
        let y = plot.minY + plot.height * (1 - (value - minCapacity) / (maxCapacity - minCapacity))

        return Text(String(format: "%.1f", value))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.green.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(Color.green.opacity(0.4), lineWidth: 1)
            )
            .position(x: x, y: max(y - 18, plot.minY + 10))
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCell("当前", text: currentValueText, tint: .green)
            metricCell("变化", text: deltaText, tint: deltaColor)
        }
    }

    private func metricCell(_ title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private var currentValueText: String {
        guard let v = capacityValues.last else { return "--" }
        return String(format: "%.1f%%", v)
    }

    private var deltaText: String {
        let vals = capacityValues.compactMap { $0 }
        guard vals.count >= 2, let first = vals.first, let last = vals.last else { return "--" }
        return String(format: "%+.1f%%", last - first)
    }

    private var deltaColor: Color {
        let vals = capacityValues.compactMap { $0 }
        guard vals.count >= 2 else { return .secondary }
        return (vals.last ?? 0) >= (vals.first ?? 0) ? .green : .red
    }

    /// 计算健康度：额定容量 ÷ 出厂容量 × 100%（不再显示系统健康度）
    private func recordHealth(_ record: HealthRecord) -> Double? {
        if let analytics = vm.analyticsRecords.first(where: { Calendar.current.isDate($0.date, inSameDayAs: record.date) }),
           let nominal = analytics.nominalChargeCapacity,
           let design = analytics.designCapacity ?? DeviceBatterySpec.current?.factoryCapacity,
           design > 0 {
            return Double(nominal) / Double(design) * 100
        }
        return record.maximumCapacity
    }
}
