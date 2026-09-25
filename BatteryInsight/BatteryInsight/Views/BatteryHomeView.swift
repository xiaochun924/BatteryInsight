import SwiftUI
import Charts

/// 「电池健康」主页面，布局参考 iOS 电池健康类 App 的通用样式：
///
/// 1. **设备信息卡**：一行一条（机型/系统、健康度、循环、温度、容量、最近检测）
/// 2. **趋势图表卡**：「健康 / 容量」切换 + 衰减速率 + 折线图（逐点数值标签）
///    + Y 轴随数据自适应（健康度 100% 上下也能完整显示，参考主流电池工具布局）
///    + 底部摘要行（预计多久降到 80% + 详情入口）
/// 3. **检测记录**：每天一张卡片（健康 %、循环次数、评级徽章、日期）
///
/// 原「电量趋势 / 趋势统计」（电量 % 曲线及其统计）已按需求删除——
/// 电量起伏与健康度无关，真正有价值的是容量随时间的衰减。
/// 原「充电检测」实时区块已拆分到「充电功率」Tab（ChargingPowerView），
/// 本页只保留与健康度强相关的静态数据。
struct BatteryHomeView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    @State private var showingAdd = false
    @State private var showingAnalytics = false
    @State private var showingTips = false
    @State private var showingReport = false
    /// 寿命预测弹窗（趋势卡「详情」按钮打开）
    @State private var showingLifetime = false
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
        .sheet(isPresented: $showingLifetime) { LifetimePredictionView() }
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
                    icon: "bolt.batteryblock", tint: .teal,
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

    /// 电池容量文案：额定容量 + 实时容量拼接（移出 ViewBuilder，避免 Void 表达式无法转成 View）
    private var capacityText: String? {
        guard let nominal = latestAnalytics?.nominalChargeCapacity else { return nil }
        var text = "\(nominal) mAh"
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

                    // 对应截图布局：衰减速率紧跟分段（「↘ -0.10%」红色向下箭头）
                    if metric == .health, let rate = BatteryAnalytics.healthDeclinePerMonth(vm.healthRecords) {
                        Label(String(format: "%.2f", rate), systemImage: "arrow.down.right")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                            .padding(.leading, 10)
                    }

                    Spacer()

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

                // 底部摘要行（对应截图：「⚖️ 正常老化 · 约 2 年 9 个月到 80%」+ 右侧「详情」入口）
                HStack(spacing: 6) {
                    if let summary = summaryText {
                        Image(systemName: "scalemass")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // 「详情」始终可点：弹出寿命预测界面（截图样式）
                    Button { showingLifetime = true } label: {
                        Text("详情")
                            .font(.footnote.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
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
        }
        // Y 轴随数据自适应（截图布局）：健康度 100% 上下也能完整显示
        .chartYScale(domain: yDomain(for: points))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .frame(height: 180)
    }

    private func label(for value: Double) -> String {
        metric == .health ? String(format: "%.1f", value) : "\(Int(value))"
    }

    /// Y 轴范围：健康度与容量都按数据自适应，并留出上下余量（也给标签留空间）。
    ///
    /// 健康度常见 100% 上下（出厂容量是标称值，实际电芯存在正公差），
    /// 不再固定 70~100——否则 101.x 的数据点会被挤出图表看不见。
    /// 对齐截图布局：数据 101.60~101.78 时，Y 轴显示 100~103。
    /// 注意局部变量不能叫 min/max——会遮蔽同名系统函数导致编译错误
    private func yDomain(for points: [(date: Date, value: Double)]) -> ClosedRange<Double> {
        guard let lo0 = points.map(\.value).min(),
              let hi0 = points.map(\.value).max() else { return 95...105 }
        let lo = floor(lo0 - 1)
        let hi = ceil(hi0 + 1)
        // 单点或数值相同：至少撑开 2 个单位，避免折线贴成一条线
        if hi - lo < 2 {
            return floor(lo0 - 2)...ceil(hi0 + 2)
        }
        return lo...hi
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
        // 同一天的分析日志（温度 / 循环 / 累计运行时长的数据源）
        let analytics = analyticsFor(record)
        return HStack(alignment: .center, spacing: 8) {
            // 列1：健康度 + 估算温度（截图对应「健康 101.60% / 15个应用卡顿」；
            // 卡顿无数据源，用估算温度占位）
            VStack(alignment: .leading, spacing: 6) {
                Text("健康 " + String(format: "%.2f", record.maximumCapacity) + "%")
                    .font(.subheadline.bold())
                    .foregroundStyle(healthTint(record.maximumCapacity))
                if let temp = analytics?.temperature {
                    Text("约 \(String(format: "%.0f", temp))℃")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("温度 --")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 列2：循环次数 + 评级徽章（截图对应「充电 91次 / 一般」）
            // 注意：analytics?.cycleCount 是 Int??（嵌套可选项），必须加括号
            // 逐层合并，否则 `??` 左结合类型不匹配会编译失败
            VStack(alignment: .leading, spacing: 6) {
                Text("循环 \(record.cycleCount ?? (analytics?.cycleCount ?? 0)) 次")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                let grade = rating(record.maximumCapacity)
                Text(grade.text)
                    .font(.caption2.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(grade.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(grade.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 列3：日期徽章 + 累计运行时长（截图对应「09/24 / 4时10分」；
            // 日志只有累计运行时间，超过 24h 折成天显示）
            VStack(alignment: .trailing, spacing: 6) {
                Text(record.date.chineseDateText)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                if let hours = analytics?.totalOperatingHours {
                    Text(runtimeText(hours))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    /// 累计运行时长文案：≥24h 折成「X 天」，否则「X 小时」
    private func runtimeText(_ hours: Double) -> String {
        if hours >= 24 {
            return "\(Int(hours / 24)) 天"
        }
        return "\(Int(hours)) 小时"
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
