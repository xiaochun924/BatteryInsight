import SwiftUI

/// 「发热」页面（Tab 3）。
///
/// 照抄 MiniWatts 的发热界面：系统发热状态 + 分级标尺 + 手机热力图 +
/// 最高温度卡片 + 最高温传感器趋势 + 各分区传感器列表。
/// 数据来自实时电源传感器引擎（HID/IOKit），模拟器上无传感器时显示说明。
struct ThermalView: View {
    @EnvironmentObject private var vm: BatteryViewModel
    @State private var power = PowerMonitor()

    private var snapshot: PowerSnapshot { power.snapshot }

    /// 每个分区最热的**实时**读数（排除 `PMU tcal` 这类校准常量）。
    private var zoneReadings: [(zone: ThermalZone, celsius: Double)] {
        snapshot.temperaturesByZone.compactMap { group in
            group.hottest.map { (group.zone, $0) }
        }
    }

    var body: some View {
        Group {
            if snapshot.temperatures.isEmpty {
                noSensorsState
            } else {
                List {
                    stateSection
                    mapSection
                    trendSection
                    zonesSection
                    modelNoteSection
                }
            }
        }
        // 液态玻璃悬浮顶栏：居中玻璃胶囊标题（无返回按钮，本页是根页面）
        .liquidGlassTopBar(title: "发热", showsBackButton: false)
        .onAppear { power.start() }
        .onDisappear { power.pause() }
    }

    // MARK: - 系统发热状态

    private var thermalTitle: String {
        switch power.thermal.state {
        case .nominal: return "正常"
        case .fair: return "轻度发热"
        case .serious: return "严重发热"
        case .critical: return "严重过热"
        @unknown default: return "未知"
        }
    }

    private var thermalEffect: String {
        switch power.thermal.state {
        case .nominal: return "充电电流不受发热限制。"
        case .fair: return "正在升温，充电电流可能被调低。"
        case .serious: return "正在节流：iOS 限制了充电电流与处理器频率。"
        case .critical: return "过热：充电暂停，直到手机降温。"
        @unknown default: return ""
        }
    }

    private var stateTint: Color {
        switch power.thermal.state {
        case .nominal: return .mwBattery
        case .fair: return .mwLoss
        default: return .mwDanger
        }
    }

    private var stateSection: some View {
        Section {
            Panel("系统发热状态", systemImage: "cpu",
                  trailing: Text(verbatim: Formatting.duration(Date.now.timeIntervalSince(power.thermal.stateSince)))) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: power.thermal.state.symbol)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(stateTint)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thermalTitle)
                                .mwReadout(size: 24)
                                .foregroundStyle(stateTint)
                            Text(thermalEffect)
                                .font(.caption)
                                .foregroundStyle(Color.mwMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    severityMeter
                    if snapshot.externalConnected, power.thermal.state.isThrottling {
                        Text("充电功率低于适配器额定值在此刻是正常的：限制来自系统，而不是充电器。")
                            .font(.caption2)
                            .foregroundStyle(Color.mwDanger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var severityMeter: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mwMuted.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [.mwBattery, .mwLoss, .mwDanger],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * power.thermal.state.severity)
                }
            }
            .frame(height: 6)
            HStack {
                ForEach([ProcessInfo.ThermalState.nominal, .fair, .serious, .critical],
                        id: \.rawValue) { state in
                    Text(thermalTitleCN(state))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(state == power.thermal.state ? stateTint : Color.mwMuted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: power.thermal.state)
    }

    private func thermalTitleCN(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "正常"
        case .fair: return "轻度发热"
        case .serious: return "严重发热"
        case .critical: return "严重过热"
        @unknown default: return "未知"
        }
    }

    // MARK: - 热力图

    private var mapSection: some View {
        Section {
            Panel("热力图·示意图", systemImage: "iphone.gen3",
                  trailing: Text(verbatim: "\(snapshot.temperatures.count) 个传感器")) {
                VStack(spacing: 12) {
                    PhoneHeatMap(readings: zoneReadings)
                        .frame(maxWidth: .infinity)
                    TemperatureScale()
                    if let hottest = snapshot.hottestSensor {
                        HStack(alignment: .top, spacing: 10) {
                            Metric(caption: "最高温度",
                                   value: String(format: "%.1f", hottest.value),
                                   unit: "°C",
                                   tint: .mwTemperature(hottest.value),
                                   footnote: Text(verbatim: hottest.name),
                                   size: 22)
                            Metric(caption: "电池",
                                   value: snapshot.batteryTemperature.map { String(format: "%.1f", $0) } ?? "—",
                                   unit: "°C",
                                   tint: snapshot.batteryTemperature.map { Color.mwTemperature($0) } ?? .primary,
                                   footnote: batteryTemperatureSource,
                                   size: 22)
                            Metric(caption: "充电芯片",
                                   value: snapshot.chargerTemperature.map { String(format: "%.1f", $0) } ?? "—",
                                   unit: "°C",
                                   tint: snapshot.chargerTemperature.map { Color.mwTemperature($0) } ?? .primary,
                                   footnote: snapshot.hottestSensor(in: .charger).map { Text(verbatim: $0.name) },
                                   size: 22)
                        }
                    }
                    Text("温度数据为实际测量值，但位置并非如此。iOS 仅报告传感器名称和数值，完全不包含坐标信息，因此各发热区域均按近年 iPhone 的常见布局绘制在固定位置——主板位于上方摄像头后部，电池位于中部，充电芯片位于接口旁。不同机型的实际内部布局存在差异。请将此图作为下方列表的图例参考，而非手机内部的真实地图。")
                        .font(.caption2)
                        .foregroundStyle(Color.mwMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// 电池温度来源：模拟器上是 IOKit 注册表，真机上是 HID 传感器，说明出来。
    private var batteryTemperatureSource: Text? {
        if snapshot.registryTemperature != nil { return Text(verbatim: "IOPMPowerSource") }
        return snapshot.hottestSensor(in: .battery).map { Text(verbatim: $0.name) }
    }

    // MARK: - 最高温趋势

    private var trendSection: some View {
        Section {
            Panel("最高温传感器（最近 3 分钟）", systemImage: "chart.line.uptrend.xyaxis") {
                LiveTemperatureChart(samples: power.live)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - 分区列表

    private func zoneTitle(_ zone: ThermalZone) -> LocalizedStringResource {
        switch zone {
        case .battery: return "电池"
        case .charger: return "充电芯片"
        case .wirelessCoil: return "无线线圈"
        case .soc: return "SoC 芯片"
        case .storage: return "存储"
        case .radio: return "射频"
        case .display: return "屏幕"
        case .camera: return "摄像头"
        case .surface: return "机身"
        case .other: return "其他传感器"
        }
    }

    private var zonesSection: some View {
        ForEach(snapshot.temperaturesByZone) { group in
            Section {
                Panel(zoneTitle(group.zone),
                      systemImage: group.zone.symbol,
                      trailing: group.hottest.map { Text(verbatim: String(format: "%.1f °C", $0)) }) {
                    VStack(spacing: 10) {
                        ForEach(group.readings) { reading in
                            BarRow(title: Text(verbatim: reading.name),
                                   detail: String(format: "%.1f °C", reading.value),
                                   fraction: (reading.value - 20) / 30,
                                   tint: .mwTemperature(reading.value))
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - 说明

    private var modelNoteSection: some View {
        Section {
            EmptyNote(text: "传感器名称、量程和是否存在因机型而异（此版本在 iPhone Air 上验证）。不可能的值会被隐藏，但仅仅不合理的值无法被识别——如果某项对你这台机型看起来不对，那它很可能就是不对的。",
                      systemImage: "exclamationmark.circle")
                .padding(.horizontal, 4)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - 无传感器（模拟器 / 尚未枚举）

    private var noSensorsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "thermometer.medium")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无温度传感器").font(.headline)
            Text("模拟器上没有温度传感器；真机上读取 HID 服务列表后会出现。\n插入充电器开始充电后，传感器会逐步出现。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
