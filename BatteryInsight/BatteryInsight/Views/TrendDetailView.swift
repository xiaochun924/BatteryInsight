import SwiftUI
import Charts

/// 趋势分析页（点击主页趋势图进入）。
/// 参考竞品「趋势分析」截图布局：
/// - 老化状态卡：正常老化 · 约 X 年 X 个月到 80%（右侧「详情」弹寿命预测）
/// - 电池健康度趋势 / 电池容量趋势 两张折线图（只显示最近 7 次记录，隐藏 XY 轴坐标值，
///   加粗折线 + 逐点胶囊数值标签 + 折线下淡绿渐变面积）
/// - 趋势分析数据：时间跨度 / 数据点数量 / 健康度变化 / 容量变化 / 平均·最高·最低
/// 竞品截图中无真实数据源的项目（电池周报 / 月报）不实现。
struct TrendDetailView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    @State private var showingLifetime = false
    @Environment(\.dismiss) private var dismiss

    /// 只显示最近 7 次记录（图表数据点，按日期升序）
    private let recentCount = 7

    private var sortedHealth: [HealthRecord] {
        vm.healthRecords.sorted { $0.date < $1.date }
    }

    private var sortedAnalytics: [AnalyticsRecord] {
        vm.analyticsRecords.sorted { $0.date < $1.date }
    }

    /// 健康度数据点（同一天多条只保留最后一条，避免重复 ID；图表只用最近 7 条）
    private var healthPoints: [(date: Date, value: Double)] {
        var byDay: [Date: (date: Date, value: Double)] = [:]
        for r in sortedHealth {
            let day = Calendar.current.startOfDay(for: r.date)
            byDay[day] = (r.date, r.maximumCapacity)
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// 容量数据点（最大容量 mAh，同天去重；图表只用最近 7 条）
    private var capacityPoints: [(date: Date, value: Double)] {
        var byDay: [Date: (date: Date, value: Double)] = [:]
        for r in sortedAnalytics {
            guard let c = r.nominalChargeCapacity else { continue }
            let day = Calendar.current.startOfDay(for: r.date)
            byDay[day] = (r.date, Double(c))
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// 图表实际渲染的健康度点：最近 7 次记录
    private var chartHealthPoints: [(date: Date, value: Double)] {
        Array(healthPoints.suffix(recentCount))
    }

    /// 图表实际渲染的容量点：最近 7 次记录
    private var chartCapacityPoints: [(date: Date, value: Double)] {
        Array(capacityPoints.suffix(recentCount))
    }

    /// 时间跨度（首尾日期间隔天数 +1，截图「14 天」）
    private func spanDays(_ points: [(date: Date, value: Double)]) -> Int {
        guard let first = points.first, let last = points.last else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        return max(1, days + 1)
    }

    /// 健康度变化（首尾差值，截图「-0.10%」）
    private func healthChange(_ points: [(date: Date, value: Double)]) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        return last.value - first.value
    }

    /// 容量变化（首尾差值，截图「-5 mAh」）
    private func capacityChange(_ points: [(date: Date, value: Double)]) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        return last.value - first.value
    }

    private func stats(_ points: [(date: Date, value: Double)]) -> (avg: Double, hi: Double, lo: Double)? {
        let values = points.map(\.value)
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count), values.max() ?? 0, values.min() ?? 0)
    }

    /// 老化状态卡文案（与主页趋势卡一致口径）。
    /// 收 `records` 参数而非直接读 `vm`：body 顶部算一次后传参给卡片，
    /// 避免每次渲染重复排序（`monthsUntil80` 内部 2 次排序 + 这里又 1 次）。
    private static func agingSummary(records: [HealthRecord]) -> String? {
        guard let latest = records.sorted(by: { $0.date < $1.date }).last,
              let months = BatteryAnalytics.monthsUntil80(records: records) else { return nil }
        let state = (BatteryAnalytics.healthDeclinePerMonth(records) ?? 0) <= 1.0 ? "正常老化" : "老化偏快"
        if months >= 12 {
            let years = Int(months) / 12
            let rest = Int(months) % 12
            let duration = rest > 0 ? "约 \(years) 年 \(rest) 个月" : "约 \(years) 年"
            return "\(state) · \(duration)到 80%"
        }
        return "\(state) · 约 \(Int(months)) 个月到 80%（当前 \(String(format: "%.1f", latest.maximumCapacity))%）"
    }

    var body: some View {
        // P0-4：派生数据（排序 + 按天去重）只算一次，各子视图共用；
        // 计算属性每次访问都重排，body 内多处引用会重复执行
        let healthPoints = self.healthPoints
        let capacityPoints = self.capacityPoints
        let chartHealth = Array(healthPoints.suffix(recentCount))
        let chartCapacity = Array(capacityPoints.suffix(recentCount))
        // N-2：老化文案含 4 次排序（latest + monthsUntil80 内 2 次 + decline 1 次），
        // body 顶部只算一次，传给卡片，避免每次渲染重排
        let agingText = Self.agingSummary(records: vm.healthRecords)
        ScrollView {
            VStack(spacing: 16) {
                agingCard(summary: agingText)
                healthTrendCard(points: chartHealth)
                capacityTrendCard(points: chartCapacity)
                statsCard(healthPoints: healthPoints, capacityPoints: capacityPoints)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        // 液态玻璃悬浮顶栏（参考 home-inventory 官方 Liquid Glass 实现）
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassTopBar(title: "趋势分析",
                        leading: { GlassCircleButton(icon: "chevron.left") { dismiss() } })
        }
        .navigationDestination(isPresented: $showingLifetime) { LifetimePredictionView() }
        // 系统导航栏已隐藏，手动恢复右滑返回手势（统一组件，见 Components.swift）
        .swipeToDismiss(dismiss)
    }

    // MARK: - 老化状态卡

    private func agingCard(summary: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "scalemass")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let summary {
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

    private func healthTrendCard(points: [(date: Date, value: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("电池健康度趋势")
                    .font(.headline)
                Spacer()
                Text("健康度(%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            trendChart(points: points,
                       format: { String(format: "%.2f", $0) },
                       domain: yDomain(points, pad: 1.0, minSpan: 2.0),
                       label: "最近7次健康度趋势",
                       summary: chartSummary(points, unit: "%"))
            .frame(height: 200)
        }
        .padding(14)
        // 中性卡底（与老化卡/统计卡一致）：绿渐变卡底在真机上会把整个页面
        // 背景染绿（LinearGradient 起始色大面积渲染），绿色只保留在图表内部
        // （折线 + 面积 + 胶囊），卡底回归系统次级分组色
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
        }
    }

    // MARK: - 容量趋势

    private func capacityTrendCard(points: [(date: Date, value: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("电池容量趋势")
                    .font(.headline)
                Spacer()
                Text("最大容量(mAh)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            trendChart(points: points,
                       format: { "\(Int($0))" },
                       domain: yDomain(points, pad: 5.0, minSpan: 20.0),
                       label: "最近7次容量趋势",
                       summary: chartSummary(points, unit: "mAh"))
            .frame(height: 200)
        }
        .padding(14)
        // 与健康度卡一致的中性卡底 + 细描边（绿色只保留在图表内部）
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
        }
    }

    // MARK: - 趋势分析数据

    private func statsCard(healthPoints: [(date: Date, value: Double)],
                           capacityPoints: [(date: Date, value: Double)]) -> some View {
        let healthStats = stats(healthPoints)
        let capacityStats = stats(capacityPoints)
        return VStack(alignment: .leading, spacing: 12) {
            Text("趋势分析数据")
                .font(.headline)

            // 时间跨度 / 数据点数量
            HStack {
                statItem(title: "时间跨度", value: "\(spanDays(healthPoints))天")
                Spacer()
                statItem(title: "数据点数量", value: "\(healthPoints.count)个", alignment: .trailing)
            }

            // 健康度变化 / 容量变化（红色，负向）
            HStack {
                changeItem(title: "健康度变化",
                           value: healthChange(healthPoints).map { String(format: "%+.2f%%", $0) } ?? "--")
                Spacer()
                changeItem(title: "容量变化",
                           value: capacityChange(capacityPoints).map { "\(Int($0)) mAh" } ?? "--",
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

    /// 图表的 VoiceOver 摘要（A11Y-2）：首尾值 + 变化方向与幅度
    private func chartSummary(_ points: [(date: Date, value: Double)], unit: String) -> String {
        guard let first = points.first, let last = points.last else { return "暂无数据" }
        let delta = last.value - first.value
        let arrow = delta >= 0 ? "上升" : "下降"
        return String(format: "从%.2f%@到%.2f%@，%@%.2f%@",
                      first.value, unit, last.value, unit,
                      arrow, abs(delta), unit)
    }

    /// 折线图：绿色加粗折线 + 折线下淡绿渐变面积 + 数据点 + 逐点胶囊数值标签。
    /// 只显示最近 7 次记录（由调用方传入），隐藏 XY 轴坐标值（刻度杂乱观感差）。
    ///
    /// 重要：Swift Charts 的 `.annotation` 在 iOS 26 真机上于 ScrollView 内不渲染
    /// （主页在 List 里正常，趋势分析页在 ScrollView 里不显示，实测确认），
    /// 所以改用官方 `chartOverlay + ChartProxy`：把每个数据点在 plot area 内
    /// 的精确坐标取出来，手动放置胶囊标签，保证真机可见。
    /// 注意 iOS 26 的 `plotFrame` 是 `Anchor<CGRect>?`，须用 GeometryReader 解引用。
    private func trendChart(points: [(date: Date, value: Double)],
                            format: @escaping (Double) -> String,
                            domain: ClosedRange<Double>,
                            label: String,
                            summary: String) -> some View {
        // X 轴范围：首尾日期；单点或空时撑开一天，避免 scale 退化
        let xRange: ClosedRange<Date>
        if let first = points.first?.date, let last = points.last?.date {
            xRange = first...last
        } else {
            let now = Date()
            xRange = now...now.addingTimeInterval(86_400)
        }
        return Chart {
            ForEach(points, id: \.date) { point in
                // 折线下方的淡绿渐变面积（视觉层次，告别单调折线；与折线同色系，
                // 顶部靠线处较深、向下渐隐，突出折线走势）
                AreaMark(
                    x: .value("日期", point.date),
                    y: .value("值", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.green.opacity(0.25), Color.green.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", point.date),
                    y: .value("值", point.value)
                )
                .foregroundStyle(Color.green)
                .interpolationMethod(.monotone)
                // 与主页趋势图一致的加粗折线（圆头圆角连接）
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("日期", point.date),
                    y: .value("值", point.value)
                )
                .foregroundStyle(Color.green)
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: xRange)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // 手动放置逐点胶囊数值（替代 .annotation，真机 ScrollView 内 annotation 不渲染）
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ForEach(points, id: \.date) { point in
                    if let plot = proxy.plotFrame,
                       let px = proxy.position(forX: point.date),
                       let py = proxy.position(forY: point.value) {
                        // plotFrame 是 Anchor<CGRect>，用 geometry 解引用拿到 plot 区域
                        let origin = geometry[plot].origin
                        Text(format(point.value))
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.thinMaterial, in: Capsule())
                            .position(x: origin.x + px,
                                      y: origin.y + py - 14)
                    }
                }
            }
        }
        // 无障碍（A11Y-2）：图表是纯图像，对 VoiceOver 提供文字摘要
        .accessibilityLabel(label)
        .accessibilityValue(summary)
    }

    /// Y 轴范围：数据自适应 + 上下余量；数值相同（贴成一条线）时撑开最小跨度。
    /// 参数不能用 min/max 命名——会遮蔽同名系统函数导致编译错误。
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
