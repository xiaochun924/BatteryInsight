import SwiftUI
import UIKit

/// 单条检测记录的详情页（布局对齐主流电池工具的记录详情）：
///
/// - 标题：「9月23日 电池记录」
/// - 顶部「电池数据 / 其他数据」分段切换：
///   - **电池数据**：电池健康卡（系统健康度 / 计算健康度 / 循环次数）+ 核心数据卡
///     （实时容量 / 出厂容量 / 温度）
///   - **其他数据**：对齐竞品口径的解读字段（满充容量范围、Qmax、电压范围、电流峰值、
///     温度区间、每日 SOC、累计运行时间……），映射关系均经真实日志逐值核对；
///     尚未解读的字段在「更多原始字段」里按原键名呈现。
///
/// 数据来源：手动记录（HealthRecord）+ 当天导入的分析日志（AnalyticsRecord）。
/// 只有手动记录时也能打开，缺的字段显示「--」。
struct RecordDetailView: View {
    let record: HealthRecord
    let analytics: AnalyticsRecord?

    @State private var tab: Tab = .battery
    @State private var copiedText: String?

    enum Tab: String, CaseIterable, Identifiable {
        case battery = "电池数据"
        case others = "其他数据"
        var id: String { rawValue }
    }

    /// 「其他数据」里有内容才显示该分段
    private var hasOtherData: Bool {
        guard let a = analytics else { return false }
        return a.rawMaxCapacity != nil || a.minFCC != nil || a.maxPackVoltage != nil
            || a.dailyMaxSoc != nil || a.lastUpdateTime != nil
            || !a.sortedExtraFields.isEmpty
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
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
        }
        // 复制成功的反馈用图标变化（✓）表达；sensoryFeedback 需要 iOS 17，部署目标是 16
    }

    private var displayTab: Tab {
        hasOtherData ? tab : .battery
    }

    private var titleText: String {
        record.date.chineseDateText + " 电池记录"
    }

    // MARK: - 电池数据

    private var batteryTab: some View {
        Group {
            Section {
                headerLabel("电池健康", icon: "heart.fill", tint: .green)
                // 手动记录优先；没有手动值时退回日志里的系统健康度
                let h = record.maximumCapacity > 0
                    ? Optional(record.maximumCapacity)
                    : analytics?.systemHealthPercent
                if let h {
                    row("系统健康度", valueText: String(format: "%.1f", h) + " %", tint: .green)
                }
                if let nominal = analytics?.nominalChargeCapacity,
                   let design = analytics?.designCapacity, design > 0 {
                    row("计算健康度", valueText: String(format: "%.1f", Double(nominal) / Double(design) * 100) + " %",
                        tint: .green,
                        caption: "出厂容量 ÷ 额定容量")
                }
                if let cycles = record.cycleCount ?? analytics?.cycleCount {
                    row("充电次数（循环）", valueText: "\(cycles) 次", tint: .blue)
                }
                if let note = record.note, !note.isEmpty {
                    row("备注", valueText: note, tint: .gray)
                }
            } footer: {
                Text("计算健康度 = 出厂容量 ÷ 额定容量，与系统健康度口径不同，仅供参考对比。")
            }

            Section {
                headerLabel("核心数据", icon: "info.circle.fill", tint: .green)
                if let v = analytics?.rawMaxCapacity {
                    row("实时容量", valueText: "\(v) mAh", tint: .green)
                }
                if let nominal = analytics?.nominalChargeCapacity {
                    row("出厂容量", valueText: "\(nominal) mAh", tint: .green)
                }
                if let temp = analytics?.temperature {
                    row("电池温度", valueText: String(format: "%.1f ℃", temp), tint: .orange)
                }
                if analytics?.nominalChargeCapacity == nil && record.maximumCapacity == nil {
                    Text("该记录没有分析日志数据，只有手动录入的数值。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 其他数据（对齐主流电池 App 的字段口径，全部来自分析日志真实键）

    private var othersTab: some View {
        Group {
            Section {
                headerLabel("其他数据", icon: "info.circle.fill", tint: .green)
                if let v = analytics?.rawMaxCapacity {
                    row("实时容量", valueText: "\(v) mAh", tint: .green)
                }
                if let v = analytics?.nominalChargeCapacity {
                    row("出厂容量", valueText: "\(v) mAh", tint: .green)
                }
                if let v = analytics?.designCapacity {
                    row("额定容量", valueText: "\(v) mAh", tint: .green)
                }
                if let hi = analytics?.maxTemperature {
                    let lo = analytics?.minTemperature
                    var text = "历史最高 \(String(format: "%.1f", hi))°"
                    if let avg = analytics?.temperature {
                        text += "，平均 \(String(format: "%.1f", avg))°"
                    }
                    if let lo { text = "历史最低 \(String(format: "%.1f", lo))°，" + text }
                    row("温度区间", valueText: text, tint: .orange)
                }
                if let lo = analytics?.minFCC, let hi = analytics?.maxFCC {
                    row("满充容量（范围）", valueText: "\(lo)–\(hi) mAh", tint: .green)
                }
                if analytics?.minQmax != nil || analytics?.qmaxCell0 != nil {
                    var text = ""
                    if let lo = analytics?.minQmax, let hi = analytics?.maxQmax {
                        text = "\(lo)–\(hi) mAh"
                    }
                    if let c = analytics?.qmaxCell0 {
                        text = text.isEmpty ? "Cell0：\(c) mAh" : text + "\nCell0：\(c) mAh"
                    }
                    row("Qmax 范围", valueText: text, tint: .green)
                }
                if let lo = analytics?.minPackVoltage, let hi = analytics?.maxPackVoltage {
                    row("电压范围",
                        valueText: "最小 \(String(format: "%.3f", lo)) V\n最大 \(String(format: "%.3f", hi)) V",
                        tint: .yellow)
                }
                if analytics?.maxChargeCurrent != nil || analytics?.maxDischargeCurrent != nil {
                    var text = ""
                    if let c = analytics?.maxChargeCurrent {
                        text = "充电峰值 ≈ \(String(format: "%.2f", c)) A"
                    }
                    if let d = analytics?.maxDischargeCurrent {
                        let line = "放电峰值 ≈ \(String(format: "%.2f", d)) A"
                        text = text.isEmpty ? line : text + "\n" + line
                    }
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
                if let h = analytics?.totalOperatingHours {
                    let hours = Int(h.rounded())
                    let grouped = NumberFormatter.localizedString(from: NSNumber(value: hours), number: .decimal)
                    row("累计运行时间",
                        valueText: "\(grouped) 小时（\(String(format: "%.1f", h / 24)) 天）",
                        tint: .gray)
                }
            } footer: {
                Text("以上字段取自分析日志的电池统计段（last_value_ 系列键），口径与主流电池工具一致；长按数值可复制核对。")
            }

            if !remainingExtraFields.isEmpty {
                Section {
                    headerLabel("更多原始字段", icon: "curlybraces", tint: .secondary)
                    ForEach(remainingExtraFields, id: \.key) { field in
                        row(cleanKey(field.key), valueText: formatNumber(field.value), tint: .gray)
                    }
                } footer: {
                    Text("日志里尚未解读的字段，按原始键名呈现。")
                }
            }
        }
    }

    /// 已在上方单独展示、不必重复出现的字段
    private var remainingExtraFields: [(key: String, value: Double)] {
        analytics?.sortedExtraFields.filter { !AnalyticsLogParser.classifies($0.key) } ?? []
    }

    // MARK: - 通用组件

    private func headerLabel(_ title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(tint)
            .padding(.bottom, 2)
    }

    /// 一行：图标 + 名称 + 数值 + 复制按钮（对应截图右侧的拷贝图标）
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

    /// 按条目名称挑个相近的图标，视觉上对齐截图
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
        case let t where t.contains("备注"):
            return "square.and.pencil"
        default:
            return "number"
        }
    }

    /// 数值格式化：整数不带小数点，其余最多保留 2 位
    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1_000_000 {
            return "\(Int(value))"
        }
        return String(format: "%.2f", value)
    }

    /// 去掉 last_value_ / batteryhealth_ 之类的前缀，展示更干净
    private func cleanKey(_ key: String) -> String {
        var name = key
        for prefix in ["last_value_", "lastvalue", "batteryhealth_", "com.apple.power.battery."] {
            if name.lowercased().hasPrefix(prefix.lowercased()) {
                name = String(name.dropFirst(prefix.count))
                break
            }
        }
        return name.isEmpty ? key : name
    }

    /// 分享文本：把该条记录的主要字段拼成一段可读文字
    private var shareText: String {
        var lines: [String] = [titleText]
        if record.maximumCapacity > 0 {
            lines.append("系统健康度：\(String(format: "%.1f", record.maximumCapacity))%")
        }
        if let cycles = record.cycleCount ?? analytics?.cycleCount {
            lines.append("循环次数：\(cycles)")
        }
        if let v = analytics?.rawMaxCapacity {
            lines.append("实时容量：\(v) mAh")
        }
        if let v = analytics?.nominalChargeCapacity {
            lines.append("出厂容量：\(v) mAh")
        }
        if let lo = analytics?.minFCC, let hi = analytics?.maxFCC {
            lines.append("满充容量（范围）：\(lo)–\(hi) mAh")
        }
        for field in analytics?.sortedExtraFields ?? [] {
            lines.append("\(cleanKey(field.key))：\(formatNumber(field.value))")
        }
        lines.append("—— 来自 BatteryInsight")
        return lines.joined(separator: "\n")
    }
}
