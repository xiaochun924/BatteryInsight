import SwiftUI
import Charts

/// 「电池健康」主页：设备信息 / 健康趋势 / 检测记录 / 充电检测卡。
struct BatteryHomeView: View {
    @EnvironmentObject private var vm: BatteryViewModel
    @State private var selectedRange: RangeKind = .week
    @State private var showingReport = false

    enum RangeKind: String, CaseIterable, Identifiable {
        case week = "近7天"
        case month = "近30天"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                deviceCard
                if vm.hasData {
                    trendCard
                }
                if vm.sessions.contains(where: { $0.isActive }) || vm.activeChargingSession != nil {
                    chargingCard
                }
                recordsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // 液态玻璃悬浮顶栏（参考 home-inventory 官方 Liquid Glass 实现）
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassTopBar(
                title: "电池健康",
                trailing: {
                    GlassCircleButton(icon: "chart.bar.doc.horizontal") { showingReport = true }
                }
            )
        }
        // 周期报告（二级页，隐藏导航栏 + 右滑返回由组件统一处理）
        .navigationDestination(isPresented: $showingReport) {
            BatteryReportView()
        }
    }

    // MARK: - 设备信息卡

    private var deviceCard: some View {
        Panel("设备", systemImage: "iphone",
              trailing: Text(verbatim: DeviceBatterySpec.current?.modelName ?? "--")) {
            if vm.hasRealLevel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(vm.levelPercent.map { String(format: "%.1f", $0) } ?? "--")
                            .mwReadout(size: 44)
                            .foregroundStyle(.primary)
                        Text("%")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.mwMuted)
                    }
                    // 电池状态胶囊 + 当日耗电速率（拉取频率高、耗电，仅在有数据时展示）
                    HStack(spacing: 6) {
                        Pill(text: Text(vm.stateText), systemImage: vm.isCharging ? "bolt.fill" : "battery.50", tint: .mwAccent)
                        if let rate = vm.drainRate {
                            Pill(text: Text(verbatim: String(format: "%.1f %%h", rate)), systemImage: "speedometer", tint: .mwMuted)
                        }
                        if let hours = vm.remainingHours {
                            Pill(text: Text(verbatim: String(format: "%.1f h", hours)), systemImage: "clock", tint: .mwMuted)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("暂无实时电量")
                        .font(.headline)
                    Text("模拟器或未授权权限时无法读取。真机首次使用请允许「电池使用信息」权限。")
                        .font(.caption)
                        .foregroundStyle(Color.mwMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 健康趋势卡

    private var filteredSamples: [BatterySample] {
        let days = selectedRange == .week ? 7 : 30
        return vm.samples.filter { Calendar.current.isDateInToday($0.date) || $0.date >= Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date() }
    }

    private var trendCard: some View {
        Panel("健康趋势", systemImage: "chart.line.uptrend.xyaxis") {
            VStack(spacing: 8) {
                Picker("范围", selection: $selectedRange) {
                    ForEach(RangeKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if filteredSamples.isEmpty {
                    Text("该范围内暂无数据")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    Chart(filteredSamples) { s in
                        LineMark(x: .value("时间", s.date),
                                 y: .value("电量 %", s.level * 100))
                            .foregroundStyle(Color.mwAccent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 140)
                }
            }
        }
    }

    // MARK: - 充电检测卡

    private var chargingCard: some View {
        Panel("充电检测", systemImage: "bolt.fill") {
            if let session = vm.activeChargingSession {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("充电中")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text(session.startDate.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(session.peakLevel * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
            } else {
                Text("检测到充电状态变化")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 检测记录

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("检测记录")
                    .font(.headline)
                Spacer()
                if !vm.healthRecords.isEmpty {
                    Text("\(vm.healthRecords.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.healthRecords.isEmpty {
                Text("还没有检测记录。点击右上角导入按钮选择电池分析日志。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(vm.healthRecords.sorted { $0.date > $1.date }) { record in
                        recordCard(record)
                    }
                }
            }
        }
    }

    /// 单条记录卡：圆角胶囊卡底 + 描边（用户确认过的视觉：ultraThinMaterial + separator 描边）。
    /// 整卡可点进详情页；点击区覆盖整张卡（contentShape 放在 label 内容层），
    /// 避免只响应文字区域的旧问题。
    private func recordCard(_ record: HealthRecord) -> some View {
        let analytics = vm.analyticsRecords.first { Calendar.current.isDate($0.date, inSameDayAs: record.date) }

        return NavigationLink(value: record) {
            HStack(spacing: 12) {
                // 左侧日期块
                VStack(spacing: 0) {
                    Text(record.date.chineseDateText)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 64, alignment: .leading)

                // 中部：健康度 + 次要信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(healthText(record))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.green)
                        if let delta = healthDeltaText(record) {
                            Text(delta)
                                .font(.caption)
                                .foregroundStyle(delta.hasPrefix("-") ? .red : .green)
                        }
                    }
                    HStack(spacing: 8) {
                        if let cycles = record.cycleCount {
                            Text("\(cycles) 次循环")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let a = analytics, let cap = a.nominalChargeCapacity {
                            Text("\(cap) mAh")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // 右侧箭头
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// 记录卡展示的健康度：有分析日志用「计算健康度」，否则用系统健康度
    private func healthText(_ record: HealthRecord) -> String {
        let value = recordHealth(record)
        return value.map { String(format: "%.1f%%", $0) } ?? "--"
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

    /// 与上一条记录的健康度差值（用于红色下降 / 绿色上升提示）
    private func healthDeltaText(_ record: HealthRecord) -> String? {
        let sorted = vm.healthRecords.sorted { $0.date > $1.date }
        guard let idx = sorted.firstIndex(where: { $0.id == record.id }),
              idx + 1 < sorted.count else { return nil }
        let current = recordHealth(record)
        let previous = recordHealth(sorted[idx + 1])
        guard let current, let previous else { return nil }
        let delta = current - previous
        guard abs(delta) > 0.05 else { return nil }
        return String(format: "%+.1f", delta)
    }
}
