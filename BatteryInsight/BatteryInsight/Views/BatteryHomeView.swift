import SwiftUI
import Charts

/// 唯一的主页面：电池健康 + 电量趋势，一屏滚动看完。
///
/// 原来是「概览 / 趋势 / 充电 / 健康」四个 Tab：
/// - **概览**：展示的是当前电量、耗电速率这类实时指标，与「电池健康度」无关
/// - **充电**：依赖 App 在前台时捕捉充电状态翻转，iOS 后台一挂起就漏记，数据不完整
///
/// 这两页已删除（连同 DashboardView / ChargingView），
/// 「健康」与「趋势」合并到这里，不再需要 TabView。
struct BatteryHomeView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    @State private var showingAdd = false
    @State private var showingAnalytics = false
    @State private var showingTips = false
    /// 电量趋势的时间范围
    @State private var range: TrendRange = .day

    enum TrendRange: String, CaseIterable, Identifiable {
        case day = "24 小时"
        case week = "7 天"
        case all = "全部"
        var id: String { rawValue }

        var hours: Double? {
            switch self {
            case .day:  return 24
            case .week: return 24 * 7
            case .all:  return nil
            }
        }
    }

    private var sortedHealth: [HealthRecord] {
        vm.healthRecords.sorted { $0.date < $1.date }
    }

    /// 列表按时间倒序展示。显式标注为数组：`reversed()` 返回的是
    /// ReversedCollection，下标不是 Int，不能直接用于 onDelete 的 IndexSet 取值
    private var reversedHealth: [HealthRecord] {
        sortedHealth.reversed()
    }

    private var latest: HealthRecord? {
        BatteryAnalytics.latestHealth(vm.healthRecords)
    }

    private var filteredSamples: [BatterySample] {
        let sorted = vm.samples.sorted { $0.date < $1.date }
        guard let hours = range.hours else { return sorted }
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        return sorted.filter { $0.date >= cutoff }
    }

    var body: some View {
        Group {
            if sortedHealth.isEmpty && filteredSamples.isEmpty {
                emptyState
            } else {
                List {
                    if sortedHealth.isEmpty {
                        importHint
                    }

                    if !sortedHealth.isEmpty {
                        Section("当前状态") { statsGrid }
                        Section("容量衰减曲线") { healthChart }
                        Section("健康记录（\(sortedHealth.count) 条）") {
                            ForEach(reversedHealth) { record in
                                healthRow(record)
                            }
                            .onDelete { offsets in
                                offsets.map { reversedHealth[$0] }
                                    .forEach { vm.deleteHealth($0) }
                            }
                        }
                    }

                    if !vm.samples.isEmpty {
                        Section("电量趋势") { levelChart }
                        Section("趋势统计") { sampleStats }
                    }
                }
            }
        }
        .navigationTitle("电池健康")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { showingAdd = true } label: {
                        Label("手动添加记录", systemImage: "plus")
                    }
                    Button { showingTips = true } label: {
                        Label("优化建议", systemImage: "lightbulb.fill")
                    }
                    Button { vm.loadDemoData() } label: {
                        Label("载入演示数据", systemImage: "sparkles")
                    }
                    Button(role: .destructive) { vm.clearAll() } label: {
                        Label("清空全部数据", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAnalytics = true } label: {
                    Label("导入日志", systemImage: "square.and.arrow.down")
                }
            }
        }
        .sheet(isPresented: $showingAdd) { addSheet }
        .sheet(isPresented: $showingAnalytics) { AnalyticsView() }
        .sheet(isPresented: $showingTips) { TipsView() }
    }

    // MARK: - 统计卡片

    private var statsGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "最大容量", value: capacityValueText, unit: "%",
                       icon: "battery.100", tint: healthTint)
            MetricCard(title: "衰减速率", value: declineText, unit: "%/月",
                       icon: "arrow.down.right", tint: .orange)
            MetricCard(title: "降至 80%", value: monthsText, unit: "个月",
                       icon: "calendar", tint: .red)
            MetricCard(title: "循环次数", value: cyclesValueText, unit: "次",
                       icon: "arrow.2.circlepath", tint: .blue)
        }
        .padding(.vertical, 4)
    }

    private var capacityValueText: String {
        guard let record = latest else { return "--" }
        return String(format: "%.0f", record.maximumCapacity)
    }

    private var cyclesValueText: String {
        guard let cycles = latest?.cycleCount else { return "--" }
        return "\(cycles)"
    }

    private var declineText: String {
        guard let rate = BatteryAnalytics.healthDeclinePerMonth(vm.healthRecords) else { return "--" }
        return String(format: "%.2f", rate)
    }

    private var monthsText: String {
        guard let months = BatteryAnalytics.monthsUntil80(records: vm.healthRecords) else { return "--" }
        return String(format: "%.0f", months)
    }

    private var healthTint: Color {
        guard let record = latest else { return .gray }
        if record.maximumCapacity < 80 { return .red }
        if record.maximumCapacity < 85 { return .orange }
        return .green
    }

    private func healthRow(_ record: HealthRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f%%", record.maximumCapacity)).font(.headline)
                Text(record.dateText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let cycles = record.cycleCount {
                Text("\(cycles) 次循环").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 容量衰减曲线

    private var healthChart: some View {
        Chart {
            ForEach(sortedHealth) { record in
                LineMark(
                    x: .value("日期", record.date),
                    y: .value("最大容量", record.maximumCapacity)
                )
                .foregroundStyle(.purple)
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("日期", record.date),
                    y: .value("最大容量", record.maximumCapacity)
                )
                .foregroundStyle(.purple)
            }
            // Apple 建议的 80% 更换阈值
            RuleMark(y: .value("更换阈值", 80.0))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(StrokeStyle(dash: [4, 3]))
        }
        .chartYScale(domain: 70...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [70, 80, 90, 100])
        }
        .frame(height: 200)
    }

    // MARK: - 电量趋势

    private var levelChart: some View {
        VStack(spacing: 12) {
            Picker("时间范围", selection: $range) {
                ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Chart(filteredSamples) { sample in
                let color: Color = sample.state.isCharging ? .green : .blue
                LineMark(
                    x: .value("时间", sample.date),
                    y: .value("电量", sample.percent)
                )
                .foregroundStyle(color)
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("时间", sample.date),
                    y: .value("电量", sample.percent)
                )
                .foregroundStyle(color)
                .symbolSize(20)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
            }
            .frame(height: 220)

            HStack(spacing: 18) {
                Label("放电", systemImage: "circle.fill").foregroundStyle(.blue)
                Label("充电", systemImage: "circle.fill").foregroundStyle(.green)
            }
            .font(.caption)
        }
    }

    private var sampleStats: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "采样点", value: "\(filteredSamples.count)", unit: "个",
                       icon: "number", tint: .gray)
            MetricCard(title: "平均电量", value: averageText, unit: "%",
                       icon: "chart.bar", tint: .blue)
            MetricCard(title: "最低电量", value: minimumText, unit: "%",
                       icon: "arrow.down", tint: .red)
            MetricCard(title: "最高电量", value: maximumText, unit: "%",
                       icon: "arrow.up", tint: .green)
        }
        .padding(.vertical, 4)
    }

    private var averageText: String {
        guard !filteredSamples.isEmpty else { return "--" }
        let avg = filteredSamples.map { $0.percent }.reduce(0, +) / Double(filteredSamples.count)
        return String(format: "%.0f", avg)
    }

    private var minimumText: String {
        guard let min = filteredSamples.map({ $0.percent }).min() else { return "--" }
        return String(format: "%.0f", min)
    }

    private var maximumText: String {
        guard let max = filteredSamples.map({ $0.percent }).max() else { return "--" }
        return String(format: "%.0f", max)
    }

    // MARK: - 导入引导

    /// 还没导入过系统分析日志时，在顶部给一个明确入口。
    /// 「最大容量 / 循环次数」iOS 不开放给第三方 App，只能从分析日志里读。
    private var importHint: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("从系统日志读取真实健康度", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.bold())
                    .foregroundStyle(.teal)
                Text("iOS 不开放「最大容量 / 循环次数」给第三方 App，但系统会把它们写进"
                     + "「设置 → 隐私与安全性 → 分析与改进 → 分析数据」里的 Analytics 日志。"
                     + "导出后导入本 App，即可得到系统原生数值。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button { showingAnalytics = true } label: {
                    Label("导入分析日志", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 手动录入

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("最大容量（%）") {
                    TextField("例如 92", text: $inputCapacity)
                        .keyboardType(.decimalPad)
                    Text("在 iPhone「设置 → 电池 → 电池健康与充电」中查看「最大容量」，把数字填到这里。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("循环次数（可选）") {
                    TextField("例如 320", text: $inputCycles)
                        .keyboardType(.numberPad)
                }
                Section("备注（可选）") {
                    TextField("例如：更换新电池后", text: $inputNote)
                }
            }
            .navigationTitle("添加健康记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(inputCapacity.isEmpty)
                }
            }
        }
    }

    @State private var inputCapacity = ""
    @State private var inputCycles = ""
    @State private var inputNote = ""

    private func save() {
        guard let capacity = Double(inputCapacity), capacity > 0, capacity <= 100 else { return }
        let cycles = Int(inputCycles)
        let note = inputNote.isEmpty ? nil : inputNote
        vm.addHealth(capacity: capacity, cycles: cycles, note: note)
        inputCapacity = ""
        inputCycles = ""
        inputNote = ""
        showingAdd = false
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有电池数据").font(.headline)
            Text("iOS 不开放「最大容量 / 循环次数」给第三方 App。\n"
                 + "最准确的做法是从系统「分析数据」导入日志，\n"
                 + "也可以手动录入：设置 → 电池 → 电池健康与充电。\n\n"
                 + "累计两次以上记录后，就能看到衰减曲线和寿命预估。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button { showingAnalytics = true } label: {
                    Label("从分析日志导入", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button { showingAdd = true } label: {
                    Label("手动添加记录", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
