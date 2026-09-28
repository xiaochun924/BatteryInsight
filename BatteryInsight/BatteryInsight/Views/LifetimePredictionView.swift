import SwiftUI
import Charts

/// 寿命预测页：按近期健康度衰减外推剩余寿命，并用胶囊趋势图展示历史健康度。
///
/// 数据：手动记录（HealthRecord）+ 当日分析日志。衰减速率由历史记录拟合，
/// 不编造不存在的点；记录太少时只展示现状，不硬给预测数字。
/// 视觉：常规材质卡底（CardContainer），顶部汇总卡片为淡绿渐变。
struct LifetimePredictionView: View {
    @EnvironmentObject private var vm: BatteryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                if records.count >= 2 {
                    trendCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // 液态玻璃悬浮顶栏（参考 home-inventory 官方 Liquid Glass 实现）；二级页左上返回
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassTopBar(title: "寿命预测",
                        leading: { GlassCircleButton(icon: "chevron.left") { dismiss() } })
        }
        // 系统导航栏已隐藏，手动恢复右滑返回手势（统一组件，见 Components.swift）
        .swipeToDismiss(dismiss)
    }

    // MARK: - 数据

    /// 参与预测的记录：近 30 天按天去重、升序，最多 30 条
    private var records: [HealthRecord] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var seen = Set<Date>()
        return vm.healthRecords
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .filter { seen.insert(calendar.startOfDay(for: $0.date)).inserted }
    }

    /// 记录对应的健康度（计算口径，见 recordHealth）
    private var healthValues: [Double] {
        records.compactMap { recordHealth($0) }
    }

    private var latestHealth: Double? {
        healthValues.last
    }

    /// 线性拟合的年化衰减速率（百分点/年）
    private var declinePerYear: Double? {
        guard healthValues.count >= 2 else { return nil }
        let xs = records.map { $0.date.timeIntervalSince1970 }
        let ys = healthValues
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let den = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard den > 0 else { return nil }
        let slopePerSecond = num / den
        return slopePerSecond * 365 * 24 * 3600
    }

    /// 从当前健康度衰减到 80% 需要的月份数
    private var monthsUntil80: Double? {
        guard let latest = latestHealth,
              let decline = declinePerYear,
              decline < -0.1,
              latest > 80 else { return nil }
        return (latest - 80) / abs(decline) * 12
    }

    // MARK: - 汇总卡

    private var summaryCard: some View {
        CardContainer(cornerRadius: 16,
                      fillStyle: AnyShapeStyle(
                          LinearGradient(colors: [.green.opacity(0.10), .white],
                                         startPoint: .top, endPoint: .bottom))) {
            VStack(alignment: .leading, spacing: 12) {
                Label("电池寿命", systemImage: "battery.100")
                    .font(.headline)
                    .foregroundStyle(.green)

                if let latest = latestHealth {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", latest))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        Text("%")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let months = monthsUntil80 {
                    Text("按当前衰减速度，预计 \(Int(months.rounded())) 个月后降至 80%（\(latestText)）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if healthValues.count < 2 {
                    Text("记录不足 2 条，暂无法外推。先导入分析日志积累记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let decline = declinePerYear {
                    if decline >= -0.1 {
                        Text("近 30 天健康度基本稳定，按当前趋势不会在短期内跌破 80%。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("当前健康度已低于 80%，请关注电池状态。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var latestText: String {
        latestHealth.map { String(format: "%.1f%%", $0) } ?? "--"
    }

    // MARK: - 趋势卡

    private var trendCard: some View {
        CardContainer(cornerRadius: 16,
                      fillStyle: AnyShapeStyle(.regularMaterial)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("历史健康度")
                        .font(.headline)
                    Spacer()
                    if let decline = declinePerYear {
                        Text("年衰减 \(String(format: "%.1f", decline))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Chart {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        if let value = healthValues[safe: index] {
                            LineMark(
                                x: .value("次序", index),
                                y: .value("健康度", value)
                            )
                            .foregroundStyle(Color.green)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: yDomain)
                .frame(height: 150)

                if let latest = latestHealth, let months = monthsUntil80 {
                    HStack(spacing: 10) {
                        Text(String(format: "%.1f%%", latest))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        Text("当前")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("约 \(Int(months.rounded())) 个月后 80%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let vals = healthValues
        guard let min = vals.min(), let max = vals.max() else { return 80...100 }
        let span = max(max - min, 1)
        return max(0, min - span * 0.5)...min(100, max + span * 0.5)
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

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
