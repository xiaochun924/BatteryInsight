import SwiftUI

/// 周期报告页：按月统计充电/温度/续航趋势，横向对比本月与上月。
/// 顶部月份切换器（上一个月 / 下一个月，上限当月）+ 三张统计卡（充电时长、平均温度、
/// 亮屏时长）+ 底部卡片（每张一行，含图标、标题、数值）+ 分享按钮。
struct BatteryReportView: View {
    /// API-2：@Observable 环境注入（替代 @EnvironmentObject）
    @Environment(BatteryViewModel.self) private var vm

    @Environment(\.dismiss) private var dismiss
    /// 当前查看的月份（默认当月；上/下月切换在此更新）
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var year = Calendar.current.component(.year, from: Date())

    /// 可上翻的边界：不能翻到当月之后（未来没有数据）
    private var isFuture: Bool {
        let now = Date()
        let curYear = Calendar.current.component(.year, from: now)
        let curMonth = Calendar.current.component(.month, from: now)
        return year > curYear || (year == curYear && month >= curMonth)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthPicker
                statsGrid
                detailCards
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        // 液态玻璃悬浮顶栏（参考 home-inventory 官方 Liquid Glass 实现）
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassTopBar(title: "周期报告",
                        leading: { GlassCircleButton(icon: "chevron.left") { dismiss() } })
        }
        // 系统导航栏已隐藏，手动恢复右滑返回手势（统一组件，见 Components.swift）
        .swipeToDismiss(dismiss)
    }

    // MARK: - 月份切换

    private var monthPicker: some View {
        HStack(spacing: 16) {
            // 上一个月：始终可点
            Button {
                withAnimation { month = month == 1 ? 12 : month - 1; if month == 12 { year -= 1 } }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("\(year)年\(month)月")
                    .font(.headline)
                Text("\(monthDays)天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 下一个月：不可超过当月
            Button {
                withAnimation { month = month == 12 ? 1 : month + 1; if month == 1 { year += 1 } }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.bold())
                    .foregroundStyle(isFuture ? .tertiary : .primary)
                    .frame(width: 36, height: 36)
                    .background(isFuture ? Color.clear : AnyShapeStyle(.regularMaterial), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFuture)
        }
        .padding(14)
        .cardStyle()
    }

    /// 当月天数
    private var monthDays: Int {
        let cal = Calendar.current
        let range = cal.range(of: .day, in: .month, for: cal.date(from: DateComponents(year: year, month: month)) ?? Date())
        return range?.count ?? 30
    }

    // MARK: - 统计卡（本月/上月两列对比）

    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(title: "充电时长", value: "\(Int(currentMonthStats.chargingMinutes / 60))小时",
                         unit: "\(Int(currentMonthStats.chargingMinutes % 60))分钟",
                         icon: "bolt.fill", tint: .green)
                statCard(title: "平均温度", value: String(format: "%.1f", currentMonthStats.avgTemp),
                         unit: "℃", icon: "thermometer.medium", tint: .orange)
                statCard(title: "亮屏时长", value: "\(Int(currentMonthStats.screenOnSeconds / 3600))小时",
                         unit: "\(Int(currentMonthStats.screenOnSeconds % 3600 / 60))分钟",
                         icon: "eye.fill", tint: .blue)
            }
            HStack(spacing: 12) {
                statCard(title: "充电时长", value: "\(Int(lastMonthStats.chargingMinutes / 60))小时",
                         unit: "\(Int(lastMonthStats.chargingMinutes % 60))分钟",
                         icon: "bolt.fill", tint: .green, isDimmed: true)
                statCard(title: "平均温度", value: String(format: "%.1f", lastMonthStats.avgTemp),
                         unit: "℃", icon: "thermometer.medium", tint: .orange, isDimmed: true)
                statCard(title: "亮屏时长", value: "\(Int(lastMonthStats.screenOnSeconds / 3600))小时",
                         unit: "\(Int(lastMonthStats.screenOnSeconds % 3600 / 60))分钟",
                         icon: "eye.fill", tint: .blue, isDimmed: true)
            }
        }
    }

    private func statCard(title: String, value: String, unit: String,
                          icon: String, tint: Color, isDimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline.bold())
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardStyle()
        .opacity(isDimmed ? 0.55 : 1)
    }

    // MARK: - 明细卡

    private var detailCards: some View {
        VStack(spacing: 12) {
            detailCard(icon: "bolt.charging", tint: .green, title: "本月充电",
                       value: "\(currentMonthStats.chargingCount) 次")
            detailCard(icon: "thermometer.high", tint: .orange, title: "最高温度",
                       value: String(format: "%.1f ℃", currentMonthStats.maxTemp))
            detailCard(icon: "battery.100", tint: .blue, title: "健康度",
                       value: currentMonthStats.healthText)
            detailCard(icon: "square.and.arrow.up", tint: .purple, title: "导出分享",
                       value: "点击分享本月报告")
                .onTapGesture { shareReport() }
        }
    }

    private func detailCard(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.bold())
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - 数据口径

    private struct MonthStats {
        var chargingMinutes: Double = 0
        var chargingCount: Int = 0
        var avgTemp: Double = 0
        var maxTemp: Double = 0
        var screenOnSeconds: Double = 0
        var healthText = "--"

        static let empty = MonthStats()
    }

    private func stats(for month: Int, year: Int) -> MonthStats {
        var s = MonthStats()
        let cal = Calendar.current
        guard let range = cal.dateInterval(of: .month, for: cal.date(from: DateComponents(year: year, month: month)) ?? Date())
        else { return .empty }

        // 充电时长：从充电会话统计（分钟）
        for session in vm.sessions where session.startDate >= range.start && session.startDate < range.end {
            s.chargingMinutes += session.durationMinutes
            s.chargingCount += 1
        }

        // 温度：从分析日志统计（只有日志才带温度）
        let monthRecords = vm.analyticsRecords.filter { $0.date >= range.start && $0.date < range.end }
        let temps = monthRecords.compactMap(\.temperature)
        if !temps.isEmpty {
            s.avgTemp = temps.reduce(0, +) / Double(temps.count)
            s.maxTemp = temps.max() ?? 0
        }

        // 亮屏时长：从分析日志统计（秒）
        s.screenOnSeconds = monthRecords.reduce(0) { $0 + ($1.screenOnSeconds ?? 0) }

        // 健康度：取当月最后一条健康记录
        let monthHealth = vm.healthRecords.filter { $0.date >= range.start && $0.date < range.end }
        if let last = monthHealth.max(by: { $0.date < $1.date }) {
            s.healthText = String(format: "%.2f%%", last.maximumCapacity)
        } else if let latest = vm.healthRecords.max(by: { $0.date < $1.date }),
                  latest.date < range.start {
            s.healthText = "\(String(format: "%.2f%%", latest.maximumCapacity))（截至上期）"
        }
        return s
    }

    private var currentMonthStats: MonthStats { stats(for: month, year: year) }
    private var lastMonthStats: MonthStats {
        let (m, y) = month == 1 ? (12, year - 1) : (month - 1, year)
        return stats(for: m, year: y)
    }

    // MARK: - 分享

    private func shareReport() {
        let lines = [
            "电池周期报告（\(year)年\(month)月）",
            "",
            "本月充电：\(Int(currentMonthStats.chargingMinutes / 60))小时\(Int(currentMonthStats.chargingMinutes % 60))分钟，共 \(currentMonthStats.chargingCount) 次",
            "平均温度：\(String(format: "%.1f", currentMonthStats.avgTemp)) ℃",
            "最高温度：\(String(format: "%.1f", currentMonthStats.maxTemp)) ℃",
            "亮屏时长：\(Int(currentMonthStats.screenOnSeconds / 3600))小时\(Int(currentMonthStats.screenOnSeconds % 3600 / 60))分钟",
            "健康度：\(currentMonthStats.healthText)",
        ]
        let text = lines.joined(separator: "\n")

        // 系统分享面板。COR-1：从激活的前台 UIWindowScene 取 keyWindow 弹窗，
        // 不再用 scenes.first（可能取到后台场景导致分享面板不弹出）
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let root = scene.keyWindow?.rootViewController {
            let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            root.present(vc, animated: true)
        }
    }
}
