import SwiftUI

/// 「适配器」页面（Tab 4）。
///
/// UI 照抄 MiniWatts 的适配器页：未连接时给出说明 + 实时供电轨；
/// 连接后显示 实际功耗 vs 额定功率 / 握手信息 / 供电档位 / 实时供电轨 /
/// 线缆与连接。数据来自 USB-PD 握手（IOKit）与 HID 电源传感器。
struct AdapterView: View {
    @EnvironmentObject private var vm: BatteryViewModel
    /// MiniWatts 实时监控引擎（@Observable，每秒一个 tick）
    @State private var power = PowerMonitor()

    private var snapshot: PowerSnapshot { power.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if snapshot.externalConnected {
                    headlinePanel
                    identityPanel
                    profilesPanel
                    railsPanel
                    connectionPanel
                } else {
                    notConnectedPanel
                    railsPanel
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // 液态玻璃悬浮顶栏：居中玻璃胶囊标题（无返回按钮，本页是根页面）
        .liquidGlassTopBar(title: "适配器", showsBackButton: false)
        .onAppear { power.start() }
        .onDisappear { power.pause() }
    }

    // MARK: 未连接

    private var notConnectedPanel: some View {
        Panel("未连接", systemImage: "powerplug") {
            EmptyNote(text: "接入充电器以读取其握手信息。USB-PD 适配器会广播包含电压与电流的供电规格列表；手机选择其中一个档位，此页面会显示所选档位以及当前实际的功率流动情况。",
                      systemImage: "cable.connector")
        }
    }

    // MARK: 实际功耗 vs 额定功率

    private var headlinePanel: some View {
        Panel("实际功耗 vs 额定功率", systemImage: "gauge.with.dots.needle.67percent",
              trailing: snapshot.adapterSource.map { Text(verbatim: $0) }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(snapshot.inputWatts.map(Formatting.watts) ?? "—")
                        .mwReadout(size: snapshot.inputWatts == nil ? 30 : 44)
                        .foregroundStyle(snapshot.inputWatts == nil ? Color.mwMuted.opacity(0.55) : Color.mwAccent)
                    Text(verbatim: "W")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.mwMuted)
                    Text("于")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mwMuted)
                        .padding(.horizontal, 2)
                    Text(snapshot.adapterRatedWatts.map { String(format: "%.0f", $0) } ?? "—")
                        .mwReadout(size: 26)
                    Text("W 额定")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mwMuted)
                }

                if let utilisation = snapshot.adapterUtilisation {
                    BarRow(title: Text("适配器利用率"),
                           detail: "\(Int(utilisation * 100))%",
                           fraction: utilisation,
                           tint: utilisation > 0.75 ? .mwBattery : .mwLoss)
                }

                if snapshot.inputWatts == nil, snapshot.adapterIsWireless {
                    EmptyNote(text: "无线充电没有输入电流传感器，无法与额定功率对比。下面的电压和电流是无线充电板协商出的档位——它是一个上限，实际功率流动在此基础上变化。",
                              systemImage: "wave.3.right")
                } else if let reason = headroomReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Color.mwMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 这页真正值得回答的问题是「为什么没有拉满额定功率」，
    /// 与其让用户从四个数字里自己推断，不如直接写出来。
    private var headroomReason: LocalizedStringResource? {
        guard let utilisation = snapshot.adapterUtilisation, utilisation < 0.75 else { return nil }
        if power.thermal.state.isThrottling {
            return "远低于适配器额定功率，而系统正在热节流——当前的瓶颈是发热，不是充电器。"
        }
        if snapshot.isChargingOnHold {
            return "充电处于暂停状态，所以几乎不取电。优化电池充电或充电上限就是这样显示的。"
        }
        if let percent = snapshot.percent, percent > 80 {
            return "电量超过 80% 后充电转入恒压阶段，功率下降是正常的电池化学特性，不是充电器不给力。"
        }
        if snapshot.isWirelessInput {
            return "无线充电被限制在远低于线充能达到的功率。"
        }
        if isSagging {
            return "接口电压远低于协商值，手机为维持电压压住了电流。这是线缆或插头的问题，不是充电器。"
        }
        return "实际功耗远低于适配器额定功率。细线缆、共享接口或手机主动放弃的档位都可能导致这种情况。"
    }

    // MARK: 握手信息

    private var identityPanel: some View {
        Panel("握手信息", systemImage: "person.text.rectangle") {
            VStack(spacing: 0) {
                DetailRow(label: "名称", value: snapshot.adapterName)
                DetailRow(label: "制造商", value: snapshot.adapterManufacturer)
                DetailRow(label: "型号", value: snapshot.adapterModel)
                DetailRow(label: "序列号", value: snapshot.adapterSerial)
                DetailRow(label: "来源", value: snapshot.adapterSource)
                DetailRow(label: "功率档", value: snapshot.adapterPowerTier.map(String.init))
                DetailRow(label: "协商上限", value: snapshot.negotiatedProfile?.label)
                DetailRow(label: "传输方式", value: DetailRow.transportName(wireless: snapshot.adapterIsWireless))
            }
        }
    }

    // MARK: 供电档位

    private var profilesPanel: some View {
        Panel("供电档位", systemImage: "list.bullet.rectangle",
              trailing: snapshot.adapterProfiles.isEmpty ? nil : Text(verbatim: "\(snapshot.adapterProfiles.count)")) {
            if snapshot.adapterProfiles.isEmpty {
                EmptyNote(text: "该适配器没有发布 PD 档位菜单。传统 USB-A 充电器和部分无线充电板只报告单一电压与电流。")
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshot.adapterProfiles) { profile in
                        ProfileRow(profile: profile,
                                   isActive: profile.index == snapshot.negotiatedProfile?.index)
                    }
                }
            }
        }
    }

    // MARK: 实时供电轨

    /// 电压与电流的原始传感器读数，按充电 IC 两侧分组。
    /// 上面所有派生数字的地基。
    private var railsPanel: some View {
        Panel("实时供电轨", systemImage: "bolt.horizontal") {
            let rails: [RailRow] = [
                RailRow(id: "usb", name: "USB-C 输入",
                        voltage: snapshot.usbInputVoltage, current: snapshot.usbInputCurrent, tint: .mwAccent),
                RailRow(id: "wireless", name: "无线输入",
                        voltage: snapshot.wirelessInputVoltage, current: snapshot.wirelessInputCurrent, tint: .mwWireless),
                RailRow(id: "battery", name: "电池侧",
                        voltage: snapshot.batteryRailVoltage, current: snapshot.batteryRailCurrent, tint: .mwBattery),
            ]
            VStack(spacing: 10) {
                ForEach(rails) { rail in
                    let (voltage, current, tint) = (rail.voltage, rail.current, rail.tint)
                    HStack {
                        Text(rail.name)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(voltage.map { String(format: "%.2f V", $0) } ?? "—")
                            .mwMono(size: 12)
                            .foregroundStyle(voltage == nil ? Color.mwMuted : Color.primary)
                        Text(verbatim: "×").font(.caption2).foregroundStyle(Color.mwMuted)
                        Text(current.map { String(format: "%.2f A", $0) } ?? "—")
                            .mwMono(size: 12)
                            .foregroundStyle(current == nil ? Color.mwMuted : Color.primary)
                        Text(watts(voltage, current).map { String(format: "%.1f W", $0) } ?? "—")
                            .mwMono(size: 12, weight: .semibold)
                            .foregroundStyle(tint)
                            .frame(width: 54, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func watts(_ voltage: Double?, _ current: Double?) -> Double? {
        guard let voltage, let current else { return nil }
        return voltage * current
    }

    // MARK: 线缆与连接

    private var connectionPanel: some View {
        Panel("线缆与连接", systemImage: "cable.connector.horizontal",
              trailing: power.pathResistance.map { Text("\($0.sampleCount) 个样本") }) {
            if let resistance {
                VStack(alignment: .leading, spacing: 12) {
                    if isSagging { sagBanner }
                    HStack(alignment: .top, spacing: 10) {
                        Metric(caption: "通路电阻",
                               value: String(format: "%.0f", resistance.milliohms),
                               unit: "mΩ",
                               tint: resistanceTint(resistance.milliohms),
                               footnote: resistance.fitted
                                   ? Text("在整个协商区间拟合")
                                   : Text("单样本估算"),
                               size: 22)
                        Metric(caption: "电压跌落",
                               value: snapshot.inputVoltageDropVolts.map { String(format: "%.2f", $0) } ?? "—",
                               unit: "V",
                               tint: isSagging ? .mwDanger : Color.primary,
                               footnote: snapshot.usbInputVoltage.map { Text("\(String(format: "%.2f V", $0)) 在接口处") },
                               size: 22)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Metric(caption: "通路损耗",
                               value: snapshot.usbInputCurrent.map {
                                   Formatting.watts(resistance.milliohms / 1000 * $0 * $0)
                               } ?? "—",
                               unit: "W",
                               tint: .mwLoss,
                               footnote: Text("按当前电流"),
                               size: 22)
                        Metric(caption: "电流利用率",
                               value: snapshot.inputCurrentUtilisation.map { String(format: "%.0f", $0 * 100) } ?? "—",
                               unit: "%",
                               tint: (snapshot.inputCurrentUtilisation ?? 1) < 0.6 ? .mwLoss : Color.primary,
                               footnote: Text("占可用的电流"),
                               size: 22)
                    }
                    Text(resistanceVerdict(resistance.milliohms))
                        .font(.caption)
                        .foregroundStyle(Color.mwMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    provenance
                }
            } else if snapshot.isWirelessInput || snapshot.adapterIsWireless {
                EmptyNote(text: "无线充电没有线缆也没有输入电流传感器，无从测量。",
                          systemImage: "wave.3.right")
            } else {
                EmptyNote(text: "等待手机取电到足以测量跌落。电流低于约 150 mA 时没有可除的数。",
                          systemImage: "chart.xyaxis.line")
            }
        }
    }

    /// 要展示的电阻值，以及它来自拟合还是单样本。
    /// 有拟合优先用拟合：它不需要参考电压，只要电流移动幅度足够就比单样本更可靠。
    private var resistance: (milliohms: Double, fitted: Bool)? {
        if let estimate = power.pathResistance { return (estimate.milliohms, true) }
        if let single = snapshot.inputPathMilliohms { return (single, false) }
        return nil
    }

    /// 快照知道电气特征；发热、充电暂停和接近满电是低功耗的无辜解释，只有监控器知道。
    private var isSagging: Bool {
        guard snapshot.isInputSagging, !power.thermal.state.isThrottling,
              !snapshot.isChargingOnHold else { return false }
        return (snapshot.percent ?? 0) <= 90
    }

    private var sagBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.mwDanger)
            Text("供电轨在负载下塌陷。手机实际取电远低于充电器提供的档位，接口电压也远低于协商值——电流被压住以阻止电压进一步下跌。换一根线试试：如果跌落变小，问题在线缆。")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.mwDanger.opacity(0.12))
        )
    }

    /// 数字从哪来，就直说。两种方法可信度不同，决定要不要换线的读者
    /// 有权知道自己看到的是哪一种。
    @ViewBuilder
    private var provenance: some View {
        let text: Text = {
            if let estimate = power.pathResistance {
                let spread = String(format: "%.2f A", estimate.currentSpread)
                let quality = "\(Int(estimate.fitQuality * 100))%"
                return Text("在 \(spread) 的电流摆动范围内拟合，其中 \(quality) 落在拟合线上。")
            }
            let contract = snapshot.adapterVoltageMillivolts.map { String(format: "%.2f V", Double($0) / 1000) } ?? "—"
            return Text("单样本估算，对照协商电压 \(contract)。该值是上限而非实测，请按数量级理解。一旦电流开始变化（80% 后的涓流、热节流、手机自身负载），会被无需参考电压的拟合替代。")
        }()
        text
            .font(.caption2)
            .foregroundStyle(Color.mwMuted.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
        Text("无论哪种方式，测的都是整条通路——充电器自身稳压、线缆和两个插头——而不是线缆单独。最适合在同一充电器上比较不同线缆。")
            .font(.caption2)
            .foregroundStyle(Color.mwMuted.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 刻意使用粗分档。数值包含充电器输出阻抗和两组触点，
    /// 精确阈值反而是虚假精度——这里只区分「正常」和「值得换线」。
    private func resistanceTint(_ milliohms: Double) -> Color {
        switch milliohms {
        case ..<200: .mwBattery
        case ..<400: .primary
        default: .mwLoss
        }
    }

    private func resistanceVerdict(_ milliohms: Double) -> LocalizedStringResource {
        switch milliohms {
        case ..<200:
            "低。这条通路没有任何东西拖累充电。"
        case ..<400:
            "长线或细线常见。会以热量形式损耗少量功率，在这个电流下不太可能改变充电速度。"
        default:
            "对充电通路来说偏高。更细或更长的线、磨损的插头、松动的接触都长这样。在同一充电器上换线是判断方法。"
        }
    }
}

/// 实时供电轨的一行。用具名类型而非元组，使标签可以是 `LocalizedStringResource`，
/// 行可以自带标识。
private struct RailRow: Identifiable {
    let id: String
    let name: LocalizedStringResource
    let voltage: Double?
    let current: Double?
    let tint: Color
}

struct ProfileRow: View {
    let profile: PDProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Color.mwAccent : Color.mwMuted.opacity(0.5))
            Text(verbatim: profile.label)
                .mwMono(size: 13, weight: isActive ? .semibold : .regular)
            Spacer()
            Text(String(format: "%.0f W", profile.watts))
                .mwReadout(size: 14, weight: .semibold)
                .foregroundStyle(isActive ? Color.mwAccent : Color.mwMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.mwAccent.opacity(0.12) : Color.mwMuted.opacity(0.06))
        )
    }
}

/// 标签在左、值在右；没有值时整行隐藏。
struct DetailRow: View {
    private let label: Text
    /// 恒为测量值或系统上报值——序列号、瓦数、时间戳——不做本地化。
    let value: String?

    /// 翻译过的标签。
    init(label: LocalizedStringResource, value: String?) {
        self.label = Text(label)
        self.value = value
    }

    /// 硬件名或字典键，原样显示。
    init(rawLabel: String, value: String?) {
        self.label = Text(verbatim: rawLabel)
        self.value = value
    }

    /// 充电的传输方式。是「值」而非标签，所以在这里解析成 String。
    static func transportName(wireless: Bool) -> String {
        wireless ? "无线" : "USB-C"
    }

    /// 嵌套的 IOKit 字典会以长多行字符串返回；这些单独左对齐显示，
    /// 而不是被压进右列。
    private var isLong: Bool {
        guard let value else { return false }
        return value.count > 34 || value.contains("\n")
    }

    var body: some View {
        if let value, !value.isEmpty {
            Group {
                if isLong {
                    VStack(alignment: .leading, spacing: 3) {
                        label
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mwMuted)
                        Text(verbatim: value)
                            .mwMono(size: 11)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        label
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mwMuted)
                        Spacer(minLength: 12)
                        Text(verbatim: value)
                            .mwMono(size: 12)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.mwCardStroke).frame(height: 0.5)
            }
        }
    }
}
