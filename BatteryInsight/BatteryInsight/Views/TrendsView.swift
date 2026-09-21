import SwiftUI
import Charts

/// 趋势页：电量随时间变化曲线 + 区间统计
struct TrendsView: View {
    @EnvironmentObject private var vm: BatteryViewModel
    @State private var range: TimeRange = .day

    enum TimeRange: String, CaseIterable, Identifiable {
        case day = "24 小时"
        case week = "7 天"
        case all = "全部"
        var id: String { rawValue }

        var hours: Double? {
            switch self {
            case .day:  return 24
            case .week: return 24 * 7
            case .all:  return nil
            }
        }
    }

    private var filtered: [BatterySample] {
        let sorted = vm.samples.sorted { $0.date < $1.date }
        guard let hours = range.hours else { return sorted }
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        return sorted.filter { $0.date >= cutoff }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Picker("时间范围", selection: $range) {
                                ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            chart
                            legend
                            stats
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("电量趋势")
        }
    }

    private var chart: some View {
        Chart(filtered) { sample in
            let color: Color = sample.state.isCharging ? .green : .blue
            LineMark(
                x: .value("时间", sample.date),
                y: .value("电量", sample.percent)
            )
            .foregroundStyle(color)
            .interpolationMethod(.monotone)

            PointMark(
                x: .value("时间", sample.date),
                y: .value("电量", sample.percent)
            )
            .foregroundStyle(color)
            .symbolSize(20)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
        }
        .frame(height: 250)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var legend: some View {
        HStack(spacing: 18) {
            Label("放电", systemImage: "circle.fill").foregroundStyle(.blue)
            Label("充电", systemImage: "circle.fill").foregroundStyle(.green)
        }
        .font(.caption)
    }

    private var stats: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "采样点", value: "\(filtered.count)", unit: "个",
                       icon: "number", tint: .gray)
            MetricCard(title: "平均电量", value: averageText, unit: "%",
                       icon: "chart.bar", tint: .blue)
            MetricCard(title: "最低电量", value: minimumText, unit: "%",
                       icon: "arrow.down", tint: .red)
            MetricCard(title: "最高电量", value: maximumText, unit: "%",
                       icon: "arrow.up", tint: .green)
        }
    }

    private var averageText: String {
        guard !filtered.isEmpty else { return "--" }
        let avg = filtered.map { $0.percent }.reduce(0, +) / Double(filtered.count)
        return String(format: "%.0f", avg)
    }

    private var minimumText: String {
        guard let min = filtered.map({ $0.percent }).min() else { return "--" }
        return String(format: "%.0f", min)
    }

    private var maximumText: String {
        guard let max = filtered.map({ $0.percent }).max() else { return "--" }
        return String(format: "%.0f", max)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无趋势数据").font(.headline)
            Text("积累一段采样后即可看到电量变化曲线。也可以到「概览」载入演示数据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
