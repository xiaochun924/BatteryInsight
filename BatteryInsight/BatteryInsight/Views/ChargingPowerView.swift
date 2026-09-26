import Charts
import SwiftUI

/// 「充电功率」页面（Tab 2，与「电池健康」分开显示）。
///
/// 集成 MiniWatts 的实时电源传感器引擎（HID/IOKit 私有框架，侧载可用）：
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
                List {
                    heroSection
                    if power.thermal.state.isThrottling { throttleBanner }
                    batterySection
                    powerPathSection
                    sessionSection
                    liveChartSection
                    recentSessionsSection
                    if !power.sensorsAvailable { sensorNote }
                }
            }
        }
        // 液态玻璃悬浮顶栏：居中玻璃胶囊标题（无返回按钮，本页是根页面）
        .liquidGlassTopBar(title: "充电功率", showsBackButton: false)
        .onAppear { power.start() }
        .onDisappear { power.pause() }
    }

    // MARK: - 实时功率（hero）

    private var heroSection: some View {
        Section {
            VStack(spacing: 12) {
                // 功率大数字
                if let headline = power.headline {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Formatting.watts(headline.watts))
                            .font(.system(size: 46, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(plugged ? Color.yellow : Color.primary)
                        Text("W")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        Text(headline.caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("--")
                            .font(.system(size: 46, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text("W")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Text("未检测到电源读数")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // 状态胶囊
                HStack(spacing: 8) {
                    statusPill(text: Text(snapshot.statusText),
                               systemImage: plugged ? "bolt.fill" : "battery.50",
                               tint: plugged ? .yellow : .secondary)
                    if snapshot.isWirelessInput {
                        statusPill(text: Text("MagSafe"), systemImage: "wave.3.right", tint: .blue)
                    }
                    if power.thermal.lowPowerMode || snapshot.lowPowerMode {
                        statusPill(text: Text("低电量模式"), systemImage: "battery.25", tint: .orange)
                    }
                    statusPill(text: Text(power.thermal.state.title),
                               systemImage: power.thermal.state.symbol,
                               tint: thermalTint)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("充电功率检测")
        }
    }

    private var thermalTint: Color {
        switch power.thermal.state {
        case .nominal: return .green
        case .fair: return .orange
        default: return .red
        }
    }

    private func statusPill(text: Text, systemImage: String, tint: Color) -> some View {
        Label { text.font(.caption2.bold()) } icon: {
            Image(systemName: systemImage)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
        .labelStyle(.titleAndIcon)
    }

    private var throttleBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "thermometer.high")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("热节流进行中")
                        .font(.system(size: 14, weight: .semibold))
                    Text(power.thermal.state.chargingEffect)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 电池面板

    private var batterySection: some View {
        Section {
            VStack(spacing: 12) {
                if let percent = snapshot.percent {
                    HStack {
                        Label("电量", systemImage: "battery.100")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(percent)%")
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                    if let minutes = snapshot.timeRemainingMinutes {
                        HStack {
                            Text(snapshot.isCharging ? "预计充满还需" : "预计耗尽还需")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Formatting.minutesRemaining(minutes))
                                .font(.subheadline.bold())
                                .monospacedDigit()
                        }
                    }
                }
                Divider()
                HStack(alignment: .top) {
                    metricColumn(caption: "电池电压",
                                 value: snapshot.batteryVoltage.map { String(format: "%.2f", $0) } ?? "--",
                                 unit: "V")
                    metricColumn(caption: "电池电流",
                                 value: snapshot.batteryCurrent.map { String(format: "%.2f", $0) } ?? "--",
                                 unit: "A")
                    metricColumn(caption: "电池温度",
                                 value: snapshot.batteryTemperature.map { String(format: "%.1f", $0) } ?? "--",
                                 unit: "°C")
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("电池")
        }
    }

    private func metricColumn(caption: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 功率路径

    private var powerPathSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    metricColumn(caption: "充电器输入",
                                 value: snapshot.inputWatts.map(Formatting.watts) ?? "--",
                                 unit: "W")
                    metricColumn(caption: "充入电池",
                                 value: snapshot.batteryWatts.map { Formatting.watts(max($0, 0)) } ?? "--",
                                 unit: "W")
                }
                HStack(alignment: .top) {
                    metricColumn(caption: "损耗为热",
                                 value: snapshot.conversionLossWatts.map(Formatting.watts) ?? "--",
                                 unit: "W")
                    metricColumn(caption: "转换效率",
                                 value: snapshot.conversionEfficiency.map { String(format: "%.0f", $0) } ?? "--",
                                 unit: "%")
                }
                if let input = snapshot.inputWatts, input > 0.2,
                   let battery = snapshot.batteryWatts, battery > 0 {
                    // 输入 vs 存储：一条横条让损耗有大小
                    let stored = CGFloat(min(battery / input, 1))
                    GeometryReader { geometry in
                        HStack(spacing: 2) {
                            Capsule()
                                .fill(Color.green)
                                .frame(width: max(2, geometry.size.width * stored - 1))
                            Capsule()
                                .fill(Color.orange.opacity(0.7))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("存储到电芯").font(.caption2).foregroundStyle(.green)
                        Spacer()
                        Text("系统负载 + 损耗").font(.caption2).foregroundStyle(.orange)
                    }
                }
                if plugged && snapshot.inputWatts == nil && snapshot.isWirelessInput {
                    Text("无线充电中：充电 IC 暴露线圈电压但无电流可配，输入功率无法测量，仅能测量到达电芯的部分。充电器自报的参数是上限而非读数。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("功率路径")
        }
    }

    // MARK: - 本次充电会话

    private var sessionSection: some View {
        Section {
            if power.currentSession != nil {
                let totals = power.sessionTotals
                VStack(spacing: 12) {
                    HStack {
                        Label("本次充电时长", systemImage: "sum")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatting.duration(power.currentSession?.duration ?? 0))
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                    HStack(alignment: .top) {
                        metricColumn(caption: "充电器已输送",
                                     value: totals.measuredInputWattHours.map { String(format: "%.2f", $0) } ?? "--",
                                     unit: "Wh")
                        metricColumn(caption: "存储到电芯",
                                     value: String(format: "%.2f", totals.batteryWattHours),
                                     unit: "Wh")
                    }
                    HStack(alignment: .top) {
                        metricColumn(caption: "充入电量",
                                     value: String(format: "%.0f", totals.batteryMilliAmpHours),
                                     unit: "mAh")
                        metricColumn(caption: "往返效率",
                                     value: totals.efficiencyPercent.map { String(format: "%.0f", $0) } ?? "--",
                                     unit: "%")
                    }
                }
                .padding(.vertical, 6)
            } else {
                Text("插入充电器开始测量。App 在前台时能量由实时传感器积分，拔出时保存到历史。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            }
        } header: {
            Text("本次充电")
        }
    }

    // MARK: - 最近 3 分钟趋势

    private var liveChartSection: some View {
        Section {
            if power.live.isEmpty {
                Text("等待传感器数据…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Chart(power.live) { sample in
                    LineMark(x: .value("时间", sample.date),
                             y: .value("充电器输入 W", sample.inputWatts))
                        .foregroundStyle(.yellow)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    if sample.batteryWatts > 0 {
                        LineMark(x: .value("时间", sample.date),
                                 y: .value("充入电池 W", sample.batteryWatts))
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }
                }
                .chartYAxisLabel("W")
                .frame(height: 140)
                HStack(spacing: 14) {
                    legendDot(color: .yellow, text: "充电器输入")
                    legendDot(color: .green, text: "充入电池", dashed: true)
                    Spacer()
                    Text("\(power.live.count) 个样本")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("最近 3 分钟")
        }
    }

    private func legendDot(color: Color, text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 14, height: 2.5)
                .opacity(dashed ? 0.7 : 1)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 历史充电会话

    private var recentSessionsSection: some View {
        Section {
            if power.sessions.isEmpty {
                Text("还没有完成的充电会话。拔出充电器后这里会显示积分能量。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(power.sessions.prefix(6)) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(session.start.formatted(.dateTime.month().day().hour().minute()))
                                .font(.subheadline.bold())
                            Spacer()
                            Text(Formatting.duration(session.duration))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        HStack(spacing: 12) {
                            Text("\(session.gainedPercent)%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let wh = session.totals.measuredInputWattHours {
                                Text("\(String(format: "%.2f", wh)) Wh")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if session.peakInputWatts > 0 {
                                Text("峰值 \(String(format: "%.1f", session.peakInputWatts)) W")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if let adapter = session.adapterName {
                                Text(adapter)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("历史充电会话")
        }
    }

    // MARK: - 传感器说明

    private var sensorNote: some View {
        Section {
            Text("未找到 HID 电源传感器。模拟器上这是正常的（IOKit 读的是 Mac 的电池）；真机上充电器插入后会出现。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
        } header: {
            Text("传感器")
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
