import SwiftUI

// MARK: - 寿命预测模型

/// 寿命预测结果：基于已有记录线性外推的容量衰减预估。
/// 口径统一写在 BatteryAnalytics.lifetimeForecast 注释里，算法估算，仅供参考。
struct LifetimeForecast {
    /// 每日循环次数（总循环 ÷ 已使用天数）
    let dailyCycleCount: Double?
    /// 总容量衰减速率 mAh/天（健康度月衰减 × 额定容量 ÷ 30）
    let totalLossPerDay: Double?
    /// 自然老化 mAh/天
    let naturalLossPerDay: Double?
    /// 循环磨损 mAh/天
    let cycleLossPerDay: Double?
    /// 老化状态：正常老化 / 老化偏快 / 暂无数据
    let agingState: String
    /// 双轨状态：双轨均衡 / 自然老化主导 / 循环磨损主导 / 暂无数据
    let trackBalance: String
    /// 状态提示文案
    let hint: String
    /// 跌到 80% 还需月数
    let monthsUntil80: Double?
    /// 跌到 90% 还需月数
    let monthsUntil90: Double?
    /// 未来预测：[(月数, 容量保留 %)]
    let futureRetentions: [(months: Int, retention: Double)]?
}

extension BatteryAnalytics {

    /// 生成寿命预测。
    ///
    /// 算法口径（线性外推，估算值，仅供参考）：
    /// 1. 每日循环次数 = 最新循环次数 ÷ 已使用天数
    ///    （已使用天数 = 首次使用日期 DOFU → 最新记录日；无 DOFU 用最早记录日）
    /// 2. 总容量衰减速率 mAh/天 = 健康度月衰减(%) × 额定容量 ÷ 30
    ///    （健康度口径比单条容量更稳：容量首尾差值受额定/实时公差影响大）
    /// 3. 双轨分解：
    ///    - 循环磨损每日 = 每次循环损耗（额定容量 × 0.02% 经验值）× 每日循环次数
    ///    - 自然老化每日 = 总衰减速率 − 循环磨损每日（不低于 0）
    /// 4. 未来预测保留% = (当前容量 − 月衰减 mAh × 月数) ÷ 额定容量 × 100，钳制 [0, 100]
    /// 5. 跌到 80% / 90% 时间 = (最新健康度 − 目标) ÷ 月衰减(%)，按月线性外推
    static func lifetimeForecast(health: [HealthRecord],
                                 analytics: [AnalyticsRecord]) -> LifetimeForecast {
        let sortedA = analytics.sorted { $0.date < $1.date }
        let first = sortedA.first
        let last = sortedA.last

        // 注意：`a?.b ?? c?.d` 中 a?.b / c?.d 都是嵌套可选项（Int?? / Date??），
        // `??` 泛型推断存在歧义风险；这里全部先解一层再合并，保证编译稳定。
        var design: Int?
        if let d = last?.designCapacity {
            design = d
        } else if let n = last?.nominalChargeCapacity {
            design = n
        }
        var current: Int?
        if let r = last?.rawMaxCapacity {
            current = r
        } else if let n = last?.nominalChargeCapacity {
            current = n
        }

        // 已使用天数（首次使用日期 DOFU → 最新记录日；无 DOFU 用最早记录日）
        var firstDay: Date?
        if let d = first?.firstUseDate {
            firstDay = d
        } else if let d = first?.date {
            firstDay = d
        }
        var lastDay: Date?
        if let d = last?.date {
            lastDay = d
        } else if let d = health.sorted { $0.date < $1.date }.last?.date {
            lastDay = d
        }
        var days: Double?
        if let f = firstDay, let l = lastDay, l > f {
            days = l.timeIntervalSince(f) / 86_400
        }

        // 每日循环次数
        var cpd: Double?
        if let cycles = last?.cycleCount, let d = days, d > 0 {
            cpd = Double(cycles) / d
        }

        // 总容量衰减速率（健康度口径）
        var total: Double?
        if let rate = healthDeclinePerMonth(health), let cap = design,
           rate > 0, cap > 0 {
            total = rate / 100 * Double(cap) / 30
        }

        // 双轨分解
        var natural: Double?
        var cycle: Double?
        if let t = total {
            let perCycle = Double(design ?? 4900) * 0.0002
            let cyclePerDay = (cpd ?? 0) * perCycle
            if cyclePerDay >= t {
                cycle = t
                natural = 0
            } else {
                cycle = cyclePerDay
                natural = t - cyclePerDay
            }
        }

        // 未来预测
        var future: [(months: Int, retention: Double)]?
        if let cur = current, let cap = design, cap > 0, let t = total {
            let monthly = t * 30
            future = [1, 3, 6].map { m in
                let retention = (Double(cur) - monthly * Double(m)) / Double(cap) * 100
                return (m, min(max(retention, 0), 100))
            }
        }

        // 老化状态
        let rate = healthDeclinePerMonth(health)
        let aging: String
        if let r = rate {
            aging = r <= 1.0 ? "正常老化" : "老化偏快"
        } else {
            aging = "暂无数据"
        }

        // 双轨状态
        var balance = "暂无数据"
        var hint = "继续记录数据观察趋势"
        if let n = natural, let c = cycle, (n + c) > 0 {
            let ratio = n / (n + c)
            if ratio >= 0.6 {
                balance = "自然老化主导"
                hint = "自然老化占比较高，温度与存放方式是关键"
            } else if ratio <= 0.4 {
                balance = "循环磨损主导"
                hint = "循环磨损占比较高，建议浅充浅放"
            } else {
                balance = "双轨均衡"
                hint = "双轨接近，继续记录数据观察趋势"
            }
        }

        // 跌到 80% / 90%
        let m80 = monthsUntil80(records: health)
        var m90: Double?
        if let latest = latestHealth(health), let r = rate,
           r > 0, latest.maximumCapacity > 90 {
            m90 = (latest.maximumCapacity - 90) / r
        }

        return LifetimeForecast(
            dailyCycleCount: cpd,
            totalLossPerDay: total,
            naturalLossPerDay: natural,
            cycleLossPerDay: cycle,
            agingState: aging,
            trackBalance: balance,
            hint: hint,
            monthsUntil80: m80,
            monthsUntil90: m90,
            futureRetentions: future)
    }

    /// 月数 → 「约 X 年 Y 个月 / 约 X 个月 / 少于 1 个月」
    static func durationText(_ months: Double) -> String {
        guard months >= 1 else { return "少于 1 个月" }
        if months >= 12 {
            let years = Int(months) / 12
            let rest = Int(months) % 12
            return rest > 0 ? "约 \(years) 年 \(rest) 个月" : "约 \(years) 年"
        }
        return "约 \(Int(months)) 个月"
    }
}

// MARK: - 寿命预测界面（截图样式）

/// 寿命预测：主页趋势卡「详情」按钮弹出。
/// 布局参考截图：状态徽章 → 80%/90% 里程碑 → 免责提示 → 未来预测 → 双轨损耗分析 → 依据说明。
struct LifetimePredictionView: View {
    @EnvironmentObject private var vm: BatteryViewModel
    @Environment(\.dismiss) private var dismiss

    /// 依据说明展开状态
    @State private var showBasis = false

    private var forecast: LifetimeForecast {
        BatteryAnalytics.lifetimeForecast(health: vm.healthRecords, analytics: vm.analyticsRecords)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                milestoneRow
                disclaimer
                futureCard
                wearCard
                basisCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .liquidGlassTopBar(
            title: "寿命预测",
            // 截图右上角为绿色对勾确认，点击关闭
            trailing: {
                Button { dismiss() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(width: 40, height: 40)
                        .glassCircleBackground()
                }
                .buttonStyle(.plain)
            }
        )
    }

    // MARK: 状态卡（正常老化 + 双轨均衡 + 提示 + 每日次数）

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(forecast.agingState)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
                Text(forecast.trackBalance)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.teal.opacity(0.15), in: Capsule())
                    .foregroundStyle(.teal)
                Spacer()
            }
            HStack(spacing: 6) {
                Image(systemName: "scalemass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(forecast.hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let cpd = forecast.dailyCycleCount {
                Label(String(format: "%.2f 次/天", cpd), systemImage: "arrow.2.circlepath")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
        }
        .cardStyle()
    }

    // MARK: 里程碑（跌到 80% / 90% 的预估时间，并排两卡）

    private var milestoneRow: some View {
        HStack(spacing: 12) {
            milestoneCard(target: 80, months: forecast.monthsUntil80)
            milestoneCard(target: 90, months: forecast.monthsUntil90)
        }
    }

    private func milestoneCard(target: Int, months: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("跌到 \(target)% 的预估时间")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(months.map { BatteryAnalytics.durationText($0) } ?? "继续记录")
                .font(.title2.bold())
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: 免责提示

    private var disclaimer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("数据虽是基于算法做出预测，但结果仅供参考！")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: 未来预测（1 / 3 / 6 个月容量保留）

    private var futureCard: some View {
        VStack(spacing: 0) {
            sectionHeader("未来预测")
            if let future = forecast.futureRetentions {
                ForEach(future, id: \.months) { item in
                    Divider()
                    HStack {
                        Text("\(item.months) 个月")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(String(format: "%.1f%%", item.retention))
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 9)
                }
            } else {
                Text("继续记录数据后可预测")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .cardStyle()
    }

    // MARK: 双轨损耗分析（自然老化 / 循环磨损）

    private var wearCard: some View {
        VStack(spacing: 10) {
            sectionHeader("双轨损耗分析")
            HStack(alignment: .top, spacing: 12) {
                wearColumn(title: "自然老化", value: forecast.naturalLossPerDay)
                wearColumn(title: "循环磨损", value: forecast.cycleLossPerDay)
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "scalemass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(forecast.hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let cpd = forecast.dailyCycleCount {
                Label(String(format: "%.2f 次/天", cpd), systemImage: "arrow.2.circlepath")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
        }
        .cardStyle()
    }

    private func wearColumn(title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.2f mAh/天", $0) } ?? "--")
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 依据说明（可展开）

    private var basisCard: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showBasis.toggle() }
            } label: {
                HStack {
                    Text("这个数据的依据是什么？")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showBasis ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if showBasis {
                VStack(alignment: .leading, spacing: 8) {
                    Text("预测基于你已记录的数据做线性外推，口径如下：")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    basisRow("每日循环次数", "总循环次数 ÷ 已使用天数（自首次使用日起）")
                    basisRow("容量衰减速率", "健康度月衰减 × 额定容量 ÷ 30 天")
                    basisRow("自然老化", "总衰减 − 循环磨损（每次循环按额定容量 0.02% 估算）")
                    basisRow("循环磨损", "每次循环损耗 × 每日循环次数")
                    basisRow("未来保留率", "当前容量 − 月衰减 × 月数，再除以额定容量")
                    Text("数据点越多，预测越稳；样本仅 1~2 条时结果波动大，仅供参考。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .cardStyle()
    }

    private func basisRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.footnote.bold())
                .foregroundStyle(.primary)
                .frame(width: 88, alignment: .leading)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: 通用小组件

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.headline)
            Spacer()
        }
        .padding(.bottom, 2)
    }
}

// MARK: - 卡片样式

private extension View {
    /// 液态玻璃卡片：圆角材质底 + 均匀内边距
    func cardStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
