import SwiftUI
import UIKit

/// 单条检测记录的详情页 —— 布局对齐主流电池工具的「9月24日 电池记录」界面：
///
/// - 顶部「电池数据 / 其他数据」分段切换：
///   - **电池数据**：电池健康（计算健康度大字 + 2×2 指标格：衰减稳定性 / 电芯一致性 /
///     充电次数 / 电池状态）+ 当日续航（当天未插电时长）+ 核心数据（额定容量 / 出厂容量）
///   - **其他数据**：温度区间、运行时长、满充容量范围、Qmax、电压、电流、每日 SOC、
///     记录更新时间等日志细节字段。
/// - 只展示日志 / 机型规格的真实数据；没有数据源的字段（亮屏时长、主动充电、
///   卡顿记录等）一律不显示，不编造数值。
///
/// 数据来源：手动记录（HealthRecord）+ 当天导入的分析日志（AnalyticsRecord）。
/// 只有手动记录时也能打开，缺的字段自动隐藏。
struct RecordDetailView: View {
    let record: HealthRecord
    let analytics: AnalyticsRecord?

    @State private var tab: Tab = .battery
    @State private var copiedText: String?
    @State private var showUsageDetail = false

    enum Tab: String, CaseIterable, Identifiable {
        case battery = "电池数据"
        case others = "其他数据"
        var id: String { rawValue }
    }

    /// 「其他数据」里有内容才显示该分段
    private var hasOtherData: Bool {
        guard let a = analytics else { return false }
        return a.rawMaxCapacity != nil || factoryCapacity != nil || a.minFCC != nil
            || a.maxPackVoltage != nil || a.dailyMaxSoc != nil || a.lastUpdateTime != nil
            || a.maxTemperature != nil
    }

    var body: some View {
        List {
            if hasOtherData {
                Section {
                    Picker("分类", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            switch displayTab {
            case .battery: batteryTab
            case .others: othersTab
            }
        }
        // 液态玻璃悬浮顶栏（参考 home-inventory 官方 Liquid Glass 实现）
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassTopBar(
                title: titleText,
                leading: { GlassCircleButton(icon: "chevron.left") { dismiss() } },
                trailing: {
                    // 分享：Button + 系统分享面板（不用 ShareLink，保证玻璃圆底样式）
                    GlassCircleButton(icon: "square.and.arrow.up") { presentShareSheet() }
                }
            )
        }
        // 复制成功的反馈用图标变化（✓）表达；部署目标 iOS 26，可用 sensoryFeedback
        .sensoryFeedback(.success, trigger: copiedText)
        // 「查看详情」：续航详情弹窗
        .sheet(isPresented: $showUsageDetail) {
            UsageDetailSheet(analytics: analytics)
        }
    }

    private var displayTab: Tab {
        hasOtherData ? tab : .battery
    }

    private var titleText: String {
        record.date.chineseDateText + " 电池记录"
    }

    /// 出厂容量：iOS 26 日志里没有 DesignCapacity，按机型取官方标称值；
    /// 老日志里真有 DesignCapacity 时以日志为准。
    private var factoryCapacity: Int? {
        DeviceBatterySpec.current?.factoryCapacity ?? analytics?.designCapacity
    }

    private var nominalCapacity: Int? {
        analytics?.nominalChargeCapacity
    }

    /// 计算健康度：额定容量 ÷ 出厂容量 × 100%（不再显示系统健康度）
    private var healthPercent: Double? {
        guard let n = nominalCapacity, let f = factoryCapacity, f > 0 else { return nil }
        return Double(n) / Double(f) * 100
    }

    /// 衰减稳定性：出厂容量 − 额定容量（正值，mAh）
    private var degradedCapacity: Int? {
        guard let n = nominalCapacity, let f = factoryCapacity, f > n else { return nil }
        return f - n
    }

    /// 电芯一致性：最大 Qmax − 最小 Qmax（mAh）
    private var cellConsistency: Int? {
        guard let hi = analytics?.maxQmax, let lo = analytics?.minQmax, hi >= lo else { return nil }
        return hi - lo
    }

    private var cycleCount: Int? {
        record.cycleCount ?? analytics?.cycleCount
    }

    /// 电池状态：基于计算健康度的简单分级
    private var batteryState: (text: String, color: Color)? {
        guard let h = healthPercent else { return nil }
        if h >= 95 { return ("优秀", .green) }
        if h >= 80 { return ("正常", .green) }
        return ("需关注", .orange)
    }

    /// 当日未插电时长文案：「X小时Y分钟」
    private var unpluggedText: String? {
        guard let s = analytics?.unpluggedDurationSeconds, s > 0 else { return nil }
        return durationText(seconds: s)
    }

    /// 当日亮屏时长文案（秒 → X小时Y分钟）
    private var screenOnText: String? {
        guard let s = analytics?.screenOnSeconds, s > 0 else { return nil }
        return durationText(seconds: s)
    }

    /// 当日后台唤醒时长文案（秒 → X小时Y分钟）
    private var awakeText: String? {
        guard let s = analytics?.awakeSeconds, s > 0 else { return nil }
        return durationText(seconds: s)
    }

    /// 当日充电时长文案（分钟 → X小时Y分钟）
    private var chargingText: String? {
        guard let m = analytics?.chargingMinutes, m > 0 else { return nil }
        return durationText(seconds: Double(m) * 60)
    }

    /// 秒数 → 「X小时Y分钟」（不足 1 小时只显示分钟）
    private func durationText(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = total % 3600 / 60
        if hours == 0 { return "\(minutes)分钟" }
        return "\(hours)小时\(minutes)分钟"
    }

    // MARK: - 电池数据

    private var batteryTab: some View {
        Group {
            Section {
                headerLabel("电池健康", icon: "heart.fill", tint: .green)
                metricGrid()
            }

            if unpluggedText != nil || screenOnText != nil
                || awakeText != nil || chargingText != nil {
                Section {
                    if let t = screenOnText {
                        row("亮屏时长", valueText: t, tint: .green,
                            caption: "当天屏幕点亮累计时长")
                    }
                    if let t = chargingText {
                        row("充电时长", valueText: t, tint: .blue,
                            caption: "当天连接电源充电累计时长")
                    }
                    if let t = unpluggedText {
                        row("未插电时长", valueText: t, tint: .green,
                            caption: "当天拔掉电源的累计时长")
                    }
                } header: {
                    HStack {
                        headerLabel(record.date.chineseDateText + " 电池续航",
                                    icon: "clock.fill", tint: .green)
                        Spacer()
                        Button {
                            showUsageDetail = true
                        } label: {
                            Label("查看详情", systemImage: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                headerLabel("核心数据", icon: "info.circle.fill", tint: .green)
                if let v = nominalCapacity {
                    row("额定容量", valueText: "\(v) mAh", tint: .green)
                }
                if let v = factoryCapacity {
                    row("出厂容量", valueText: "\(v) mAh", tint: .green)
                }
                if nominalCapacity == nil && record.maximumCapacity == nil {
                    Text("该记录没有分析日志数据，只有手动录入的数值。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 3 行 × 2 列指标格（对齐截图：计算健康度 / 电池状态 / 衰减稳定性 / 电芯一致性 / 充电次数）
    private func metricGrid() -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            if let h = healthPercent {
                metricCell("计算健康度", String(format: "%.1f", h), "%",
                           tint: .green, large: true)
            }
            if let st = batteryState {
                metricCell("电池状态", st.text, "", tint: st.color)
            }
            if let d = degradedCapacity {
                metricCell("衰减稳定性", "\(d)", "mAh", tint: .orange)
            }
            if let c = cellConsistency {
                metricCell("电芯一致性", "\(c)", "mAh", tint: .blue)
            }
            if let cyc = cycleCount {
                metricCell("充电次数", "\(cyc)", "次", tint: .blue)
            }
        }
        .padding(.vertical, 4)
    }

    /// 指标格（对齐截图：大数值靠左 + 标题靠右）
    private func metricCell(_ title: String, _ value: String, _ unit: String,
                            tint: Color, large: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(large ? .title.bold() : .title3.bold())
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 其他数据（全部来自分析日志真实键）

    private var othersTab: some View {
        Group {
            Section {
                headerLabel("其他数据", icon: "info.circle.fill", tint: .green)
                if let v = analytics?.rawMaxCapacity {
                    row("实时容量", valueText: "\(v) mAh", tint: .green)
                }
                if let v = nominalCapacity {
                    row("额定容量", valueText: "\(v) mAh", tint: .green)
                }
                if let v = factoryCapacity {
                    row("出厂容量", valueText: "\(v) mAh", tint: .green)
                }
                if let text = temperatureRangeText {
                    row("温度区间", valueText: text, tint: .orange)
                }
                if let h = analytics?.totalOperatingHours {
                    let hours = Int(h.rounded())
                    let grouped = NumberFormatter.localizedString(from: NSNumber(value: hours), number: .decimal)
                    row("运行时长",
                        valueText: "\(grouped) 小时（\(String(format: "%.1f", h / 24)) 天）",
                        tint: .gray)
                }
                if let lo = analytics?.minFCC, let hi = analytics?.maxFCC {
                    row("满充容量（范围）", valueText: "\(lo)–\(hi) mAh", tint: .green)
                }
                if let text = qmaxRangeText {
                    row("Qmax 范围", valueText: text, tint: .green)
                }
                if let lo = analytics?.minPackVoltage, let hi = analytics?.maxPackVoltage {
                    row("电压范围",
                        valueText: "最小 \(String(format: "%.3f", lo)) V\n最大 \(String(format: "%.3f", hi)) V",
                        tint: .yellow)
                }
                if let text = currentDataText {
                    row("电流数据", valueText: text, tint: .blue)
                }
                if let v = analytics?.dailyMinSoc {
                    row("最低充电起始电量", valueText: "\(v)%", tint: .green)
                }
                if let v = analytics?.dailyMaxSoc {
                    row("最高充电截止电量", valueText: "\(v)%", tint: .green)
                }
                if let d = analytics?.lastUpdateTime {
                    row("记录更新时间", valueText: d.chineseDateText, tint: .gray)
                }
            } footer: {
                Text("以上字段取自分析日志的电池统计段（last_value_ 系列键），口径与主流电池工具一致；长按数值可复制核对。")
            }
        }
    }

    /// 温度区间文案：历史最高/最低/平均拼接
    private var temperatureRangeText: String? {
        guard let hi = analytics?.maxTemperature else { return nil }
        var text = "历史最高 \(String(format: "%.1f", hi))°"
        if let avg = analytics?.temperature {
            text += "，平均 \(String(format: "%.1f", avg))°"
        }
        if let lo = analytics?.minTemperature {
            text = "历史最低 \(String(format: "%.1f", lo))°，" + text
        }
        return text
    }

    /// Qmax 范围文案：范围 + Cell0 拼接
    private var qmaxRangeText: String? {
        guard analytics?.minQmax != nil || analytics?.qmaxCell0 != nil else { return nil }
        var text = ""
        if let lo = analytics?.minQmax, let hi = analytics?.maxQmax {
            text = "\(lo)–\(hi) mAh"
        }
        if let c = analytics?.qmaxCell0 {
            text = text.isEmpty ? "Cell0：\(c) mAh" : text + "\nCell0：\(c) mAh"
        }
        return text.isEmpty ? nil : text
    }

    /// 电流数据文案：充电/放电峰值拼接
    private var currentDataText: String? {
        guard analytics?.maxChargeCurrent != nil || analytics?.maxDischargeCurrent != nil else { return nil }
        var text = ""
        if let c = analytics?.maxChargeCurrent {
            text = "充电峰值 ≈ \(String(format: "%.2f", c)) A"
        }
        if let d = analytics?.maxDischargeCurrent {
            let line = "放电峰值 ≈ \(String(format: "%.2f", d)) A"
            text = text.isEmpty ? line : text + "\n" + line
        }
        return text.isEmpty ? nil : text
    }

    // MARK: - 通用组件

    private func headerLabel(_ title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(tint)
            .padding(.bottom, 2)
    }

    /// 一行：图标 + 名称 + 数值 + 复制按钮
    private func row(_ title: String, valueText: String, tint: Color, caption: String? = nil) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(tint.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: iconFor(title))
                        .font(.caption)
                        .foregroundStyle(tint)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(valueText)
                .font(.subheadline.bold())
                .monospacedDigit()
                .multilineTextAlignment(.trailing)

            Button {
                UIPasteboard.general.string = valueText
                copiedText = valueText
            } label: {
                Image(systemName: copiedText == valueText ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 1)
    }

    /// 按条目名称挑个相近的图标
    private func iconFor(_ title: String) -> String {
        switch title {
        case let t where t.contains("健康"):
            return "heart.fill"
        case let t where t.contains("容量"):
            return "battery.100"
        case let t where t.contains("电压"):
            return "bolt"
        case let t where t.contains("温度"):
            return "thermometer.medium"
        case let t where t.contains("次数") || t.contains("循环"):
            return "arrow.2.circlepath"
        case let t where t.contains("唤醒"):
            return "sun.max.fill"
        case let t where t.contains("充电"):
            return "bolt.fill"
        case let t where t.contains("时长") || t.contains("运行"):
            return "clock.fill"
        case let t where t.contains("备注"):
            return "square.and.pencil"
        default:
            return "number"
        }
    }

    /// 弹出系统分享面板（替代 ShareLink，保证按钮走液态玻璃圆底样式）
    @MainActor
    private func presentShareSheet() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let sheet = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = root.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: root.view.bounds.midX, y: 60, width: 0, height: 0)
        root.present(sheet, animated: true)
    }

    /// 分享文本：把该条记录的主要字段拼成一段可读文字
    private var shareText: String {
        var lines: [String] = [titleText]
        if let h = healthPercent {
            lines.append(String(format: "计算健康度：%.1f%%", h))
        }
        if let cycles = cycleCount {
            lines.append("充电次数（循环）：\(cycles)")
        }
        if let d = degradedCapacity {
            lines.append("衰减稳定性：\(d) mAh")
        }
        if let c = cellConsistency {
            lines.append("电芯一致性：\(c) mAh")
        }
        if let u = unpluggedText {
            lines.append("当日未插电时长：\(u)")
        }
        if let s = screenOnText {
            lines.append("当日亮屏时长：\(s)")
        }
        if let a = awakeText {
            lines.append("当日后台唤醒：\(a)")
        }
        if let c = chargingText {
            lines.append("当日充电时长：\(c)")
        }
        if let v = analytics?.rawMaxCapacity {
            lines.append("实时容量：\(v) mAh")
        }
        if let v = nominalCapacity {
            lines.append("额定容量：\(v) mAh")
        }
        if let v = factoryCapacity {
            lines.append("出厂容量：\(v) mAh")
        }
        if let h = analytics?.totalOperatingHours {
            lines.append("运行时长：\(Int(h.rounded())) 小时（\(String(format: "%.1f", h / 24)) 天）")
        }
        lines.append("—— 来自 BatteryInsight")
        return lines.joined(separator: "\n")
    }
}

/// 当日续航详情弹窗（点续航板块「查看详情」弹出）。
/// 展示当天所有可用的续航时段数据，全部来自分析日志真实字段。
private struct UsageDetailSheet: View {
    let analytics: AnalyticsRecord?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    detailRow("亮屏时长", secondsText(analytics?.screenOnSeconds), "sun.max.fill", .green)
                    detailRow("后台唤醒", secondsText(analytics?.awakeSeconds), "moon.stars.fill", .orange)
                    detailRow("充电时长", minutesText(analytics?.chargingMinutes), "bolt.fill", .blue)
                    detailRow("未插电时长", secondsText(analytics?.unpluggedDurationSeconds), "poweroutlet.type.fill", .green)
                } header: {
                    Text("时段明细")
                } footer: {
                    Text("亮屏/唤醒为 intervalUsage 段 15 分钟区间求和；充电为 SystemChargingDuration 汇总（分钟）；未插电为 UnpluggedDurationEnergyViewNew。")
                }

                if analytics?.maxTemperature != nil || analytics?.totalOperatingHours != nil {
                    Section {
                        if let r = analytics, let hi = r.maxTemperature {
                            detailRow("温度区间",
                                      temperatureText(hi, avg: r.temperature, lo: r.minTemperature),
                                      "thermometer.medium", .orange)
                        }
                        if let h = analytics?.totalOperatingHours {
                            let hours = Int(h.rounded())
                            let grouped = NumberFormatter.localizedString(from: NSNumber(value: hours), number: .decimal)
                            detailRow("运行时长", "\(grouped) 小时（\(String(format: "%.1f", h / 24)) 天）",
                                      "clock.fill", .gray)
                        }
                    } header: {
                        Text("电池状态")
                    }
                }
            }
            // 液态玻璃悬浮顶栏（参考 home-inventory 官方 Liquid Glass 实现）；左上角关闭
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                GlassTopBar(title: "续航详情",
                            leading: { GlassCircleButton(icon: "xmark") { dismiss() } })
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func secondsText(_ s: Double?) -> String {
        guard let s, s > 0 else { return "--" }
        let total = Int(s.rounded())
        let hours = total / 3600
        let minutes = total % 3600 / 60
        if hours == 0 { return "\(minutes)分钟" }
        return "\(hours)小时\(minutes)分钟"
    }

    private func minutesText(_ m: Int?) -> String {
        guard let m, m > 0 else { return "--" }
        let hours = m / 60
        let minutes = m % 60
        if hours == 0 { return "\(minutes)分钟" }
        return "\(hours)小时\(minutes)分钟"
    }

    private func temperatureText(_ hi: Double, avg: Double?, lo: Double?) -> String {
        var text = "最高 \(String(format: "%.1f", hi))°"
        if let avg { text += "，平均 \(String(format: "%.1f", avg))°" }
        if let lo { text = "最低 \(String(format: "%.1f", lo))°，" + text }
        return text
    }

    private func detailRow(_ title: String, _ value: String,
                           _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}
