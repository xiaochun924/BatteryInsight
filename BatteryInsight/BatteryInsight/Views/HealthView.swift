import SwiftUI
import Charts

/// 健康度页：因 iOS 不开放该数据，需用户手动录入「最大容量」后做衰减分析。
struct HealthView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    @State private var showingAdd = false
    @State private var inputCapacity = ""
    @State private var inputCycles = ""
    @State private var inputNote = ""
    /// 主 Tab 只有 4 个（超 5 个会被系统收进「More」），故日志与建议从这里进入
    @State private var showingAnalytics = false
    @State private var showingTips = false

    private var sorted: [HealthRecord] {
        vm.healthRecords.sorted { $0.date < $1.date }
    }

    private var latest: HealthRecord? {
        BatteryAnalytics.latestHealth(vm.healthRecords)
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.healthRecords.isEmpty {
                    emptyState
                } else {
                    List {
                        Section("当前状态") { statsGrid }
                        Section("容量衰减曲线") { chart }
                        Section("历史记录") {
                            ForEach(sorted) { record in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(format: "%.0f%%", record.maximumCapacity))
                                            .font(.headline)
                                        Text(record.dateText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let cycles = record.cycleCount {
                                        Text("\(cycles) 次循环")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                offsets.map { sorted[$0] }.forEach { vm.deleteHealth($0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("电池健康")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showingAnalytics = true
                        } label: {
                            Label("日志分析", systemImage: "doc.text.magnifyingglass")
                        }
                        Button {
                            showingTips = true
                        } label: {
                            Label("优化建议", systemImage: "lightbulb.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) { addSheet }
            .sheet(isPresented: $showingAnalytics) { AnalyticsView() }
            .sheet(isPresented: $showingTips) { TipsView() }
        }
    }

    // MARK: - 统计

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

    // MARK: - 曲线

    private var chart: some View {
        Chart {
            ForEach(sorted) { record in
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

    // MARK: - 录入

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("最大容量（%）") {
                    TextField("例如 92", text: $inputCapacity)
                        .keyboardType(.decimalPad)
                    Text("在 iPhone「设置 → 电池 → 电池健康与充电」中查看「最大容量」，把数字填到这里。iOS 不允许第三方 App 直接读取该值。")
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
            Text("还没有健康度记录").font(.headline)
            Text("iOS 不开放「最大容量 / 循环次数」给第三方 App。\n最准确的做法是从系统「分析数据」导入日志（右上角 ⋯ → 日志分析），\n也可以手动录入：设置 → 电池 → 电池健康与充电。\n\n累计两次以上记录后，就能看到衰减曲线和寿命预估。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button { showingAdd = true } label: {
                    Label("手动添加记录", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button { showingAnalytics = true } label: {
                    Label("从分析日志导入", systemImage: "square.and.arrow.down")
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
