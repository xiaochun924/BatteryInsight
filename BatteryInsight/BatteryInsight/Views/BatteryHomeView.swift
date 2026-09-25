import SwiftUI
import Charts

/// 唯一的主页面，布局参考 iOS 电池健康类 App 的通用样式：
///
/// 1. **设备信息卡**：一行一条（机型/系统、健康度、循环、温度、容量、最近检测）
/// 2. **趋势图表卡**：「健康 / 容量」切换 + 衰减速率 + 折线图（逐点数值标签）
///    + 底部摘要行（预计多久降到 80%）
/// 3. **检测记录**：每天一张卡片（健康 %、循环次数、评级徽章、日期）
///
/// 原「电量趋势 / 趋势统计」（电量 % 曲线及其统计）已按需求删除——
/// 电量起伏与健康度无关，真正有价值的是容量随时间的衰减。
struct BatteryHomeView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    @State private var showingAdd = false
    @State private var showingAnalytics = false
    @State private var showingTips = false
    @State private var showingReport = false
    /// 「导入」一步到位：直接弹系统文件管理器，不再经过中间页
    @State private var showingFileImporter = false
    @State private var showingResult = false
    /// 图表显示哪种指标。容量数据只有导入分析日志后才有，届时才出现「容量」段
    @State private var metric: ChartMetric = .health

    enum ChartMetric: String, CaseIterable, Identifiable {
        case health = "健康"
        case capacity = "容量"
        var id: String { rawValue }
    }

    // MARK: - 数据

    private var sortedHealth: [HealthRecord] {
        vm.healthRecords.sorted { $0.date < $1.date }
    }

    /// 列表按时间倒序展示。显式转成数组：`reversed()` 的下标不是 Int，
    /// 不能直接用于 onDelete 的 IndexSet 取值
    private var reversedHealth: [HealthRecord] {
        Array(sortedHealth.reversed())
    }

    private var latest: HealthRecord? { sortedHealth.last }

    private var sortedAnalytics: [AnalyticsRecord] {
        vm.analyticsRecords.sorted { $0.date < $1.date }
    }

    private var latestAnalytics: AnalyticsRecord? { sortedAnalytics.last }

    /// 是否有实际容量数据（决定图表卡要不要显示「容量」切换段）
    private var hasCapacityData: Bool {
        sortedAnalytics.contains { $0.nominalChargeCapacity != nil }
    }

    /// 图表数据点。同一天可能有多条记录（手动连加、重复导入），
    /// 按天去重（保留当天最后一条），避免 ForEach 出现重复 ID
    private var chartPoints: [(date: Date, value: Double)] {
        let raw: [(Date, Double)]
        switch metric {
        case .health:
            raw = sortedHealth.map { ($0.date, $0.maximumCapacity) }
        case .capacity:
            raw = sortedAnalytics.compactMap { record in
                record.nominalChargeCapacity.map { (record.date, Double($0)) }
            }
        }
        var byDay: [Date: (date: Date, value: Double)] = [:]
        for point in raw {
            let day = Calendar.current.startOfDay(for: point.0)
            byDay[day] = (point.0, point.1)
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    var body: some View {
        Group {
            if sortedHealth.isEmpty && sortedAnalytics.isEmpty {
                emptyState
            } else {
                List {
                    chargingCard
                    deviceCard
                    trendCard
                    recordsSection
                }
            }
        }
        // 液态玻璃悬浮顶栏：完全隐藏系统导航栏，居中玻璃胶囊标题，
        // 左上角菜单 + 右上角「+ 分析」作为顶栏动作（无返回按钮，本页是根页面）
        .liquidGlassTopBar(
            title: "电池健康",
            showsBackButton: false,
            leading: {
                Menu {
                    Button { showingAdd = true } label: {
                        Label("手动添加记录", systemImage: "plus")
                    }
                    Button { showingAnalytics = true } label: {
                        Label("日志分析", systemImage: "doc.text.magnifyingglass")
                    }
                    Button { showingTips = true } label: {
                        Label("优化建议", systemImage: "lightbulb.fill")
                    }
                    Button { showingReport = true } label: {
                        Label("周期报告", systemImage: "calendar")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            },
            trailing: {
                // 右上角「+ 分析」玻璃胶囊按钮
                Button { showingFileImporter = true } label: {
                    Label("分析", systemImage: "plus")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(vm.isImporting)
            }
        )
        .sheet(isPresented: $showingAdd) { addSheet }
        .sheet(isPresented: $showingAnalytics) { AnalyticsView() }
        .sheet(isPresented: $showingTips) { TipsView() }
        .sheet(isPresented: $showingReport) { BatteryReportView() }
        // 直接从最顶层 VC 弹系统选择器，不再包一层 sheet——
        // 中间层白卡就是"点导入先跳白屏"的来源
        .documentPicker(
            isPresented: $showingFileImporter,
            contentTypes: AnalyticsFileImporter.allowedContentTypes,
            allowsMultipleSelection: true
        ) { urls in
            Task {
                _ = await vm.importAnalyticsFiles(urls)
                showingResult = true
            }
        }
        .alert("导入结果", isPresented: $showingResult) {
            Button("好", role: .cancel) { }
        } message: {
            Text(vm.importMessage ?? "")
        }
        .overlay {
            if vm.isImporting { ImportingOverlay(stage: vm.importStage) }
        }
    }

    // MARK: - 实时充电检测卡（电池健康 + 充电检测的实时区块）

    /// 实时电量、充电状态、耗电速率、剩余可用时长，以及进行中的充电会话。
    /// 数据来自 `BatteryMonitor` 的前台采样（模拟器/后台无数据时显示「--」）。
    private var chargingCard: some View {
        Section {
            VStack(spacing: 14) {
                // 电量环 + 状态
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.15), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: batteryLevelFraction)
                            .stroke(
                                stateGradient,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Image(systemName: vm.isCharging ? "bolt.fill" : "battery.50")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(vm.isCharging ? .yellow : .green)
                            Text(batteryLevelText)
                                .font(.title2.bold())
                                .monospacedDigit()
                        }
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 10) {
                        // 充电状态
                        Label(vm.stateText, systemImage: vm.state.symbolName)
                            .font(.headline)
                            .foregroundStyle(vm.isCharging ? .yellow : .green)
                        // 耗电速率 / 剩余时长
                        if vm.isCharging {
                            if let active = vm.activeChargingSession {
                                Label("充电中 \(active.gainedPercent, format: .number.precision(.fractionLength(0)))%",
                                      systemImage: "arrow.up.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            if let rate = vm.drainRate {
                                Label("耗电 \(rate, format: .number.precision(.fractionLength(1)))%/小时",
                                      systemImage: "arrow.down.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let hours = vm.remainingHours {
                                Label("约剩 \(hours, format: .number.precision(.fractionLength(1))) 小时",
                                      systemImage: "timer")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("充电检测")
        }
    }

    /// 电量环填充比例（0~1；无真实电量时为 0）
    private var batteryLevelFraction: Double {
        guard vm.hasRealLevel else { return 0 }
        return min(max(vm.level, 0), 1)
    }

    /// 电量环文案（无真实电量时显示「--」）
    private var batteryLevelText: String {
        vm.levelPercent.map { "\(Int($0.rounded()))%" } ?? "--"
    }

    /// 电量环渐变色：充电黄色，放电/待机绿色
    private var stateGradient: LinearGradient {
        if vm.isCharging {
            return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - 设备信息卡（参考截图第一张卡片：一行一条）

    private var deviceCard: some View {
        Section {
            infoRow(
                icon: "iphone.gen3", tint: .green,
                title: UIDevice.current.name,
                accessory: {
                    // 系统版本徽章（对应截图的「iOS xx.x >」）
                    Text("iOS \(UIDevice.current.systemVersion)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }())

            if let record = latest {
                infoRow(
                    icon: "battery.100", tint: healthTint(record.maximumCapacity),
                    title: "电池健康度",
                    accessory: valueText(String(format: "%.1f", record.maximumCapacity) + " %",
                                         color: healthTint(record.maximumCapacity)))
            }
            if let cycles = latest?.cycleCount ?? latestAnalytics?.cycleCount {
                infoRow(
                    icon: "arrow.2.circlepath", tint: .blue,
                    title: "循环次数",
                    accessory: valueText("\(cycles) 次", color: .primary))
            }
            if let temp = latestAnalytics?.temperature {
                infoRow(
                    icon: "thermometer.medium", tint: .orange,
                    title: "估算温度",
                    accessory: valueText(String(format: "约 %.0f ℃", temp), color: .primary))
            }
            if let text = capacityText {
                infoRow(
                    icon: "bolt.big", tint: .teal,
                    title: "电池容量",
                    accessory: valueText(text, color: .primary))
            }
            if let date = latest?.date {
                infoRow(
                    icon: "calendar", tint: .gray,
                    title: "最近检测",
                    accessory: valueText(date.chineseDateText, color: .secondary))
            }
        } header: {
            Text("设备信息")
        }
    }

    private func infoRow(icon: String, tint: Color, title: String, accessory: some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 26)
            Text(title)
                .font(.body)
                .lineLimit(1)
            Spacer()
            accessory
        }
        .padding(.vertical, 2)
    }

    private func valueText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(color)
            .lineLimit(1)
    }

    /// 电池容量文案：出厂 + 实时拼接（移出 ViewBuilder，避免 Void 表达式无法转成 View）
    private var capacityText: String? {
        guard let nominal = latestAnalytics?.nominalChargeCapacity else { return nil }
        var text = "出厂 \(nominal) mAh"
        if let raw = latestAnalytics?.rawMaxCapacity {
            text += " / 实时 \(raw) mAh"
        }
        return text
    }

    // MARK: - 趋势图表卡（参考截图第二张卡片）

    private var trendCard: some View {
        Section {
            // 头部：「健康 / 容量」切换 + 衰减速率 + 详细分析入口
            VStack(spacing: 12) {
                HStack {
                    if hasCapacityData {
                        Picker("指标", selection: $metric) {
                            ForEach(ChartMetric.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    } else {
                        Text(metric == .health ? "健康度趋势" : "容量趋势")
                            .font(.headline)
                    }

                    Spacer()

                    if metric == .health, let rate = BatteryAnalytics.healthDeclinePerMonth(vm.healthRecords) {
                        // 对应截图的「↘ -0.06%」：衰减为正数，用红色向下箭头
                        Label(String(format: "%.2f", rate), systemImage: "arrow.down.right")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                    }

                    Button { showingAnalytics = true } label: {
                        Label("详细分析", systemImage: "arrow.up.right")
                            .font(.footnote.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                trendChart

                // 底部摘要行（对应截图的「⚖️ 正常老化 · 约 2 年 9 个月到 80%」）
                if let summary = summaryText {
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("趋势")
        }
    }

    private var trendChart: some View {
        let points = chartPoints
        return Chart {
            ForEach(points, id: \.date) { point in
                LineMark(
                    x: .value("日期", point.date),
                    y: .value(metric == .health ? "健康度" : "容量", point.value)
                )
                .foregroundStyle(Color.green)
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("日期", point.date),
                    y: .value(metric == .health ? "健康度" : "容量", point.value)
                )
                .foregroundStyle(Color.green)
                // 对应截图里每个点上方/下方的数值标签；点太多时只标首尾，避免糊成一团
                .annotation(position: .top, spacing: 6) {
                    if points.count <= 8
                        || point.date == points.first?.date
                        || point.date == points.last?.date {
                        Text(label(for: point.value))
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }
            // 健康度视图下画出 80% 更换阈值参考线
            if metric == .health {
                RuleMark(y: .value("更换阈值", 80.0))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(dash: [4, 3]))
            }
        }
        .chartYScale(domain: yDomain(for: points))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .frame(height: 180)
    }

    private func label(for value: Double) -> String {
        metric == .health ? String(format: "%.1f", value) : "\(Int(value))"
    }

    /// Y 轴范围：健康度固定 70~100；容量按数据自适应并留出余量（也给标签留空间）。
    /// 注意局部变量不能叫 min/max——会遮蔽同名系统函数导致编译错误
    private func yDomain(for points: [(date: Date, value: Double)]) -> ClosedRange<Double> {
        if metric == .health { return 70...100 }
        guard let lo = points.map(\.value).min(),
              let hi = points.map(\.value).max() else { return 0...100 }
        let pad = Swift.max(50, (hi - lo) * 0.3)
        return Swift.max(0, lo - pad)...(hi + pad)
    }

    /// 底部摘要：按当前衰减速率估算降到 80% 的时间
    private var summaryText: String? {
        guard metric == .health,
              let latest = latest,
              let months = BatteryAnalytics.monthsUntil80(records: vm.healthRecords) else { return nil }
        let state = (BatteryAnalytics.healthDeclinePerMonth(vm.healthRecords) ?? 0) <= 1.0 ? "正常老化" : "老化偏快"
        if months >= 12 {
            let years = Int(months) / 12
            let rest = Int(months) % 12
            let duration = rest > 0 ? "约 \(years) 年 \(rest) 个月" : "约 \(years) 年"
            return "\(state) · \(duration)到 80%"
        }
        return "\(state) · 约 \(Int(months)) 个月到 80%（当前 \(String(format: "%.1f", latest.maximumCapacity))%）"
    }

    // MARK: - 检测记录（参考截图底部的每日卡片）

    private var recordsSection: some View {
        Section("检测记录（\(sortedHealth.count) 条）") {
            ForEach(reversedHealth) { record in
                // 点任意一条记录 → push 详情页（电池数据 / 其他数据 分段）
                NavigationLink {
                    RecordDetailView(record: record, analytics: analyticsFor(record))
                } label: {
                    recordCard(record)
                }
            }
            .onDelete { offsets in
                offsets.map { reversedHealth[$0] }
                    .forEach { vm.deleteHealth($0) }
            }
        }
    }

    /// 取该条手动记录同一天的分析日志（详情页的数据源之一）
    private func analyticsFor(_ record: HealthRecord) -> AnalyticsRecord? {
        let day = Calendar.current.startOfDay(for: record.date)
        return sortedAnalytics.first { Calendar.current.startOfDay(for: $0.date) == day }
    }

    private func recordCard(_ record: HealthRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 40, height: 40)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Label(String(format: "%.1f", record.maximumCapacity) + " %",
                          systemImage: "battery.100")
                        .font(.subheadline.bold())
                        .foregroundStyle(healthTint(record.maximumCapacity))
                    if let cycles = record.cycleCount {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Label("\(cycles) 次", systemImage: "arrow.2.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    // 评级徽章（对应截图的「良好 / 一般」）
                    let grade = rating(record.maximumCapacity)
                    Text(grade.text)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(grade.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(grade.color)
                    if let note = record.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 日期徽章（对应截图的「09/23」）
            Text(record.date.chineseDateText)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func rating(_ health: Double) -> (text: String, color: Color) {
        switch health {
        case 95...:  return ("优秀", .green)
        case 85..<95: return ("良好", .teal)
        case 80..<85: return ("一般", .orange)
        default:     return ("较差", .red)
        }
    }

    private func healthTint(_ health: Double) -> Color {
        if health < 80 { return .red }
        if health < 85 { return .orange }
        return .green
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
                 + "也可以手动录入：设置 → 电池 → 电池健康与充电。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button { showingFileImporter = true } label: {
                    Label("从分析日志导入", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isImporting)

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

// MARK: - 解析中遮罩

/// 解析几十 MB 的日志要几秒。之前没有这个反馈，界面就是一片黑屏，
/// 看起来跟"点了没反应 / 卡死"一样。
private struct ImportingOverlay: View {
    let stage: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(stage ?? "正在解析…")
                    .font(.subheadline)
                Text("日志较大时需要几秒，请稍候")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .allowsHitTesting(true)
    }
}
