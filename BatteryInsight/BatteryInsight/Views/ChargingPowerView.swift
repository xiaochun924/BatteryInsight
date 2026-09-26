import Charts
import SwiftUI

/// 「充电功率」页面（Tab 2，与「电池健康」「发热」分开显示）。
///
/// UI 照抄 MiniWatts 的功率页：环形功率仪表盘（PowerRing）+ 电池面板 +
/// 供电路径面板 + 本次充电会话。数据来自实时电源传感器引擎
/// （HID/IOKit 私有框架，侧载可用）：
///   - 实时功率：充电器输入功率（输入电压 × 输入电流）、充入电池功率
///   - 实时电压 / 电流 / 温度（电池、充电 IC、SoC 等 HID 传感器）
///   - 充电会话：插上开始、拔出保存，能量由实时传感器积分（Wh / mAh）
///   - USB-PD 适配器信息与线缆损耗评估
/// 模拟器 / 读不到传感器时显示 "--"，不估算假数据。
struct ChargingPowerView: View {
    @EnvironmentObject private var vm: BatteryViewModel
    /// MiniWatts 实时监控引擎（@Observable，每秒一个 tick）
    @State private var power = PowerMonitor()

    private var snapshot: PowerSnapshot { power.snapshot }
    private var plugged: Bool { snapshot.externalConnected }

    var body: some View {
        Group {
            if vm.latestAnalytics == nil && !vm.sessions.contains(where: { $0.isActive }) && !power.sensorsAvailable {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        heroPanel
                        if power.thermal.state.isThrottling { throttlePanel }
                        batteryPanel
                        powerPathPanel
                        sessionPanel
                        liveChartPanel
                        sessionsPanel
                        if !power.sensorsAvailable { sensorNotePanel }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        // iOS 26 官方液态玻璃导航栏：玻璃材质 + 滚动收成胶囊（根页面无返回按钮）
        .navigationTitle("充电功率")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.glass, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .onAppear { power.start() }
        .onDisappear { power.pause() }
    }

    // MARK: - Hero（环形仪表）

    /// 满量程：适配器额定功率已知时以其为刻度，让表盘显示余量
    private var fullScale: Double {
        guard plugged else { return 15 }
        if snapshot.inputWatts == nil { return max(snapshot.adapterRatedWatts ?? 25, 10) }
        return max(snapshot.adapterRatedWatts ?? 30, 5)
    }

    private var glowColor: Color {
        if power.thermal.state.isThrottling { return .mwDanger }
        if snapshot.isWirelessInput { return .mwWireless }
        return plugged ? .mwAccent : .mwLoss
    }

    private var statusTextCN: String {
        if snapshot.isChargingOnHold { return "充电暂停" }
        if snapshot.fullyCharged && snapshot.externalConnected { return "已充满" }
        if snapshot.isCharging { return snapshot.isFinishingCharge ? "涓流充电" : "充电中" }
        if snapshot.externalConnected { return "已插电，未充电" }
        return "使用电池"
    }

    private var thermalTitleCN: String {
        switch power.thermal.state {
        case .nominal: return "正常"
        case .fair: return "轻度发热"
        case .serious: return "严重发热"
        case .critical: return "严重过热"
        @unknown default: return "未知"
        }
    }

    private var thermalTint: Color {
        switch power.thermal.state {
        case .nominal: return .mwBattery
        case .fair: return .mwLoss
        default: return .mwDanger
        }
    }

    private var heroPanel: some View {
        Panel {
            VStack(spacing: 14) {
                PowerRing(inputWatts: power.headline?.watts,
                          batteryWatts: plugged && snapshot.inputWatts != nil ? snapshot.batteryWatts : nil,
                          fullScale: fullScale,
                          caption: power.headline?.caption,
                          tint: glowColor)
                    .padding(.top, 4)
                    // 表盘在面板中水平居中（MiniWatts 原版 Panel 内容默认左对齐）
                    .frame(maxWidth: .infinity)

                HStack(spacing: 6) {
                    Pill(text: Text(statusTextCN),
                         systemImage: plugged ? "bolt.fill" : "battery.50",
                         tint: plugged ? .mwAccent : .mwMuted)
                    if snapshot.isWirelessInput {
                        Pill(text: Text("MagSafe"), systemImage: "wave.3.right", tint: .mwWireless)
                    }
                    if snapshot.holdIsInferred {
                        Pill(text: Text("推断"), systemImage: "questionmark.circle", tint: .mwLoss)
                    }
                    if power.thermal.lowPowerMode || snapshot.lowPowerMode {
                        Pill(text: Text("低电量模式"), systemImage: "battery.25", tint: .mwLoss)
                    }
                    Pill(text: Text(thermalTitleCN),
                         systemImage: power.thermal.state.symbol,
                         tint: thermalTint)
                }
                // 状态胶囊行同样水平居中
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var throttlePanel: some View {
        Panel {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "thermometer.high")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.mwDanger)
                VStack(alignment: .leading, spacing: 3) {
                    Text("热节流进行中")
                        .font(.system(size: 14, weight: .semibold))
                    Text(thermalEffectCN)
                        .font(.caption)
                        .foregroundStyle(Color.mwMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.mwDanger.opacity(0.45), lineWidth: 1)
        )
    }

    private var thermalEffectCN: String {
        switch power.thermal.state {
        case .nominal: return "充电电流不受发热限制。"
        case .fair: return "正在升温，充电电流可能被调低。"
        case .serious: return "正在节流：iOS 限制了充电电流与处理器频率。"
        case .critical: return "过热：充电暂停，直到手机降温。"
        @unknown default: return ""
        }
    }

    // MARK: - 电池面板

    private var batteryPanel: some View {
        Panel("电池", systemImage: "battery.100") {
            VStack(spacing: 12) {
                if let percent = snapshot.percent {
                    BarRow(title: Text("电池电量"),
                           detail: "\(percent)%",
                           fraction: Double(percent) / 100,
                           tint: percent <= 20 ? .mwDanger : .mwBattery,
                           subtitle: snapshot.timeRemainingMinutes.map { minutes in
                               Text(snapshot.isCharging
                                    ? "预计充满还需 \(Formatting.minutesRemaining(minutes))"
                                    : "预计耗尽还需 \(Formatting.minutesRemaining(minutes))")
                           })
                }
                HStack(alignment: .top, spacing: 10) {
                    Metric(caption: "电芯电压",
                           value: snapshot.batteryVoltage.map { String(format: "%.2f", $0) } ?? "—",
                           unit: "V", size: 20)
                    Metric(caption: "电芯电流",
                           value: snapshot.batteryCurrent.map { String(format: "%.2f", $0) } ?? "—",
                           unit: "A",
                           tint: (snapshot.batteryCurrent ?? 0) > 0 ? .mwBattery : .primary,
                           size: 20)
                    Metric(caption: "电芯温度",
                           value: snapshot.batteryTemperature.map { String(format: "%.1f", $0) } ?? "—",
                           unit: "℃",
                           tint: snapshot.batteryTemperature.map { Color.mwTemperature($0) } ?? .primary,
                           size: 20)
                }
            }
        }
    }

    // MARK: - 供电路径

    private var efficiencyTint: Color {
        guard let efficiency = snapshot.conversionEfficiency else { return .primary }
        return efficiency >= 85 ? .mwBattery : (efficiency >= 70 ? .mwLoss : .mwDanger)
    }

    private var powerPathPanel: some View {
        Panel("供电路径", systemImage: "arrow.triangle.branch",
              trailing: snapshot.adapterUtilisation.map { Text(verbatim: "占适配器 \(Int($0 * 100))%") }) {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Metric(caption: "来自充电器",
                           value: snapshot.inputWatts.map(Formatting.watts) ?? "—",
                           unit: "W", tint: .mwAccent, size: 22)
                    Metric(caption: "充入电芯",
                           value: snapshot.batteryWatts.map { Formatting.watts(max($0, 0)) } ?? "—",
                           unit: "W", tint: .mwBattery, size: 22)
                }
                HStack(alignment: .top, spacing: 10) {
                    Metric(caption: "发热损耗",
                           value: snapshot.conversionLossWatts.map(Formatting.watts) ?? "—",
                           unit: "W", tint: .mwLoss, size: 22)
                    Metric(caption: "转换效率",
                           value: snapshot.conversionEfficiency.map { String(format: "%.0f", $0) } ?? "—",
                           unit: "%",
                           tint: efficiencyTint,
                           footnote: Text("电芯功率 ÷ 充电器功率"),
                           size: 22)
                }
                if let input = snapshot.inputWatts, input > 0.2,
                   let battery = snapshot.batteryWatts, battery > 0 {
                    powerFlowBar(input: input, toBattery: battery)
                }
                if plugged && snapshot.inputWatts == nil && snapshot.isWirelessInput {
                    EmptyNote(text: "无线充电中：充电 IC 暴露线圈电压但无电流可配，输入功率无法测量，仅能测量到达电芯的部分。充电器自报的参数是上限而非读数。",
                              systemImage: "wave.3.right")
                }
            }
        }
    }

    /// 输入 vs 存储：一条横条让损耗有大小
    private func powerFlowBar(input: Double, toBattery: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                let stored = CGFloat(min(toBattery / input, 1))
                HStack(spacing: 2) {
                    Capsule()
                        .fill(Theme.gradient(.mwBattery))
                        .frame(width: max(2, geometry.size.width * stored - 1))
                    Capsule()
                        .fill(Theme.gradient(.mwLoss).opacity(0.7))
                }
            }
            .frame(height: 8)
            HStack {
                Text("充入电芯").font(.caption2).foregroundStyle(Color.mwBattery)
                Spacer()
                Text("系统负载 + 损耗").font(.caption2).foregroundStyle(Color.mwLoss)
            }
        }
    }

    // MARK: - 本次充电会话

    private var sessionPanel: some View {
        Panel("本次充电", systemImage: "sum",
              trailing: power.currentSession.map { Text(verbatim: Formatting.duration($0.duration)) } ?? Text("空闲")) {
            if power.currentSession != nil {
                let totals = power.sessionTotals
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Metric(caption: "充电器已输送",
                               value: totals.measuredInputWattHours.map { String(format: "%.2f", $0) } ?? "—",
                               unit: "Wh", tint: .mwAccent, size: 20)
                        Metric(caption: "存储到电芯",
                               value: String(format: "%.2f", totals.batteryWattHours),
                               unit: "Wh", tint: .mwBattery, size: 20)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Metric(caption: "充入电量",
                               value: String(format: "%.0f", totals.batteryMilliAmpHours),
                               unit: "mAh", size: 20)
                        Metric(caption: "往返效率",
                               value: totals.efficiencyPercent.map { String(format: "%.0f", $0) } ?? "—",
                               unit: "%", tint: .mwLoss, size: 20)
                    }
                }
            } else {
                EmptyNote(text: "插入充电器开始测量。App 在前台时能量由实时传感器积分，拔出时保存到历史。",
                          systemImage: "powerplug")
            }
        }
    }

    // MARK: - 最近 3 分钟趋势

    private var liveChartPanel: some View {
        Panel("最近 3 分钟", systemImage: "waveform.path.ecg",
              trailing: Text(verbatim: "\(power.live.count) 个样本")) {
            if power.live.isEmpty {
                EmptyNote(text: "等待传感器数据…", systemImage: "clock")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Chart(power.live) { sample in
                        LineMark(x: .value("时间", sample.date),
                                 y: .value("充电器输入 W", sample.inputWatts))
                            .foregroundStyle(Color.mwAccent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                        if sample.batteryWatts > 0 {
                            LineMark(x: .value("时间", sample.date),
                                     y: .value("充入电池 W", sample.batteryWatts))
                                .foregroundStyle(Color.mwBattery)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartYAxisLabel("W")
                    .frame(height: 130)
                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            Capsule().fill(Color.mwAccent).frame(width: 14, height: 2.5)
                            Text("来自充电器").font(.caption2).foregroundStyle(Color.mwMuted)
                        }
                        HStack(spacing: 5) {
                            Capsule().fill(Color.mwBattery).frame(width: 14, height: 2.5)
                            Text("充入电芯").font(.caption2).foregroundStyle(Color.mwMuted)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 历史充电会话

    private var sessionsPanel: some View {
        Panel("历史充电会话", systemImage: "clock.arrow.circlepath") {
            if power.sessions.isEmpty {
                EmptyNote(text: "还没有完成的充电会话。拔出充电器后这里会显示积分能量。", systemImage: "tray")
            } else {
                VStack(spacing: 10) {
                    ForEach(power.sessions.prefix(6)) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.start.formatted(.dateTime.month().day().hour().minute()))
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(Formatting.duration(session.duration))
                                    .mwMono(size: 12)
                                    .foregroundStyle(Color.mwMuted)
                            }
                            HStack(spacing: 12) {
                                Text("\(session.gainedPercent)%")
                                    .font(.footnote)
                                    .foregroundStyle(Color.mwMuted)
                                if let wh = session.totals.measuredInputWattHours {
                                    Text("\(String(format: "%.2f", wh)) Wh")
                                        .font(.footnote)
                                        .foregroundStyle(Color.mwMuted)
                                }
                                if session.peakInputWatts > 0 {
                                    Text("峰值 \(String(format: "%.1f", session.peakInputWatts)) W")
                                        .font(.footnote)
                                        .foregroundStyle(Color.mwMuted)
                                }
                                Spacer()
                            }
                        }
                        .padding(.vertical, 2)
                        if session.id != power.sessions.prefix(6).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - 传感器说明

    private var sensorNotePanel: some View {
        Panel("传感器", systemImage: "sensor") {
            EmptyNote(text: "未找到 HID 电源传感器。模拟器上这是正常的（IOKit 读的是 Mac 的电池）；真机上充电器插入后会出现。",
                      systemImage: "exclamationmark.triangle")
        }
    }

    // MARK: - 空态（模拟器 / 完全无数据时）

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无充电数据").font(.headline)
            Text("连接电源开始充电后，\nApp 会自动记录充电状态与耗电速率。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
