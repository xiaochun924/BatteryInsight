import SwiftUI
import Charts

/// 趋势分析页（点击主页趋势图进入）。
/// 参考竞品「趋势分析」截图布局：
/// - 老化状态卡：正常老化 · 约 X 年 X 个月到 80%（右侧「详情」弹寿命预测）
/// - 电池健康度趋势 / 电池容量趋势 两张折线图
/// - 趋势分析数据：时间跨度 / 数据点数量 / 健康度变化 / 容量变化 / 平均·最高·最低
/// 竞品截图中无真实数据源的项（电池周报 / 月报）不实现。
struct TrendDetailView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    @State private var showingLifetime = false

    private var sortedHealth: [HealthRecord] {
        vm.healthRecords.sorted { $0.date < $1.date }
    }

    private var sortedAnalytics: [AnalyticsRecord] {
        vm.analyticsRecords.sorted { $0.date < $1.date }
    }

    /// 健康度数据点（同一天多条只保留最后一条，避免重复 ID）
    private var healthPoints: [(date: Date, value: Double)] {
        var byDay: [Date: (date: Date, value: Double)] = [:]
        for r in sortedHealth {
            let day = Calendar.current.startOfDay(for: r.date)
            byDay[day] = (r.date, r.maximumCapacity)
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// 容量数据点（最大容量 mAh，同天去重）
    private var capacityPoints: [(date: Date, value: Double)] {
        var byDay: [Date: (date: Date, value: Double)] = [:]
        for r in sortedAnalytics {
            guard let c = r.nominalChargeCapacity else { continue }
            let day = Calendar.current.startOfDay(for: r.date)
            byDay[day] = (r.date, Double(c))
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// 时间跨度（首尾日期间隔天数 +1，截图「14 天」）
    private var spanDays: Int {
        guard let first = healthPoints.first, let last = healthPoints.last else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        return max(1, days + 1)
    }

    /// 健康度变化（首尾差值，截图「-0.10%」）
    private var healthChange: Double? {
        guard let first = healthPoints.first, let last = healthPoints.last else { return nil }
        return last.value - first.value
    }

    /// 容量变化（首尾差值，截图「-5 mAh」）
    private var capacityChange: Double? {
        guard let first = capacityPoints.first, let last = capacityPoints.last else { return nil }
        return last.value - first.value
    }

    private var healthStats: (avg: Double, hi: Double, lo: Double)? {
        let values = healthPoints.map(\.value)
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count), values.max() ?? 0, values.min() ?? 0)
    }

    private var capacityStats: (avg: Double, hi: Double, lo: Double)? {
        let values = capacityPoints.map(\.value)
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count), values.max() ?? 0, values.min() ?? 0)
    }

    /// 老化状态卡文案（与主页趋势卡一致口径）
    private var agingSummary: String? {
        guard let latest = sortedHealth.last,
              let months = BatteryAnalytics.monthsUntil80(records: vm.healthRecords) else { return nil }
        let state = (BatteryAnalytics.healthDeclinePerMonth(vm.healthRecords) ?? 0) <= 1.0 ? "正常老化" : "老化偏快"
        if months >= 12 {
            let years = Int(months) / 12
            let rest = Int(months) % 12
            let duration = rest > 0 ? "约 \(years) 年 \(rest) 个月" : "约 \(years) 年"
            return "\(state) · \(duration)到 80%"
        }
        return "\(state) · 约 \(Int(months)) 个月到 80%（当前 \(String(format: "%.1f", latest.maximumCapacity))%）"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                agingCard
                healthTrendCard
                capacityTrendCard
                statsCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        // iOS 26 官方液态玻璃导航栏：玻璃材质 + 滚动收成胶囊；返回按钮官方自动生成
        .navigationTitle("趋势分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.glass, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .sheet(isPresented: $showingLifetime) { LifetimePredictionView() }
    }

    // MARK: - 老化状态卡

    private var agingCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "scalemass")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let summary = agingSummary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("暂无足够数据预测寿命")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { showingLifetime = true } label: {
                Text("详情")
                    .font(.footnote.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 健康度趋势

    private var healthTrendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("电池健康度趋势")
                    .font(.headline)
                Spacer()
                Text("健康度(%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            trendChart(points: healthPoints,
                       format: { String(format: "%.2f", $0) },
                       domain: yDomain(healthPoints, pad: 1.0, minSpan: 2.0))
            .frame(height: 200)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 容量趋势

    private var capacityTrendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("电池容量趋势")
                    .font(.headline)
                Spacer()
                Text("最大容量(mAh)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            trendChart(points: capacityPoints,
                       format: { "\(Int($0))" },
                       domain: yDomain(capacityPoints, pad: 5.0, minSpan: 20.0))
            .frame(height: 200)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 趋势分析数据

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("趋势分析数据")
                .font(.headline)

            // 时间跨度 / 数据点数量
            HStack {
                statItem(title: "时间跨度", value: "\(spanDays)天")
                Spacer()
                statItem(title: "数据点数量", value: "\(healthPoints.count)个", alignment: .trailing)
            }

            // 健康度变化 / 容量变化（红色，负向）
            HStack {
                changeItem(title: "健康度变化",
                           value: healthChange.map { String(format: "%+.2f%%", $0) } ?? "--")
                Spacer()
                changeItem(title: "容量变化",
                           value: capacityChange.map { "\(Int($0)) mAh" } ?? "--",
                           alignment: .trailing)
            }

            Divider()

            // 健康统计 / 容量统计 两列
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("健康统计")
                        .font(.subheadline.bold())
                    statRow("平均健康度", healthStats.map { String(format: "%.2f%%", $0.avg) } ?? "--")
                    statRow("最高健康度", healthStats.map { String(format: "%.2f%%", $0.hi) } ?? "--")
                    statRow("最低健康度", healthStats.map { String(format: "%.2f%%", $0.lo) } ?? "--")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("容量统计")
                        .font(.subheadline.bold())
                    statRow("平均容量", capacityStats.map { "\(Int($0.avg)) mAh" } ?? "--")
                    statRow("最高容量", capacityStats.map { "\(Int($0.hi)) mAh" } ?? "--")
                    statRow("最低容量", capacityStats.map { "\(Int($0.lo)) mAh" } ?? "--")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 复用小组件

    private func statItem(title: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func changeItem(title: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.footnote.bold())
        }
    }

    /// 折线图：绿色线 + 逐点数值标签（点太多时只标首尾）
    private func trendChart(points: [(date: Date, value: Double)],
                            format: @escaping (Double) -> String,
                            domain: ClosedRange<Double>) -> some View {
        Chart {
            ForEach(points, id: \.date) { point in
                LineMark(
                    x: .value("日期", point.date),
                    y: .value("值", point.value)
                )
                .foregroundStyle(Color.green)
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("日期", point.date),
                    y: .value("值", point.value)
                )
                .foregroundStyle(Color.green)
                .annotation(position: .top, spacing: 6) {
                    if points.count <= 8
                        || point.date == points.first?.date
                        || point.date == points.last?.date {
                        Text(format(point.value))
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
    }

    /// Y 轴范围：数据自适应 + 上下余量；数值相同（贴成一条线）时撑开最小跨度。
    /// 参数不能用 min/max 命名——会遮蔽系统同名函数导致编译错误。
    private func yDomain(_ points: [(date: Date, value: Double)],
                         pad: Double,
                         minSpan: Double) -> ClosedRange<Double> {
        guard let lo0 = points.map(\.value).min(),
              let hi0 = points.map(\.value).max() else { return 0...1 }
        let lo = floor(lo0 - pad)
        let hi = ceil(hi0 + pad)
        if hi - lo < minSpan {
            return floor(lo0 - minSpan / 2)...ceil(hi0 + minSpan / 2)
        }
        return lo...hi
    }
}
