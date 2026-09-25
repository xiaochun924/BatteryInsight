import SwiftUI
import Charts
import UIKit

/// 容量趋势图上的一个数据点
private struct HealthPoint: Identifiable {
    let id = UUID()
    let date: Date
    let pct: Double
}

/// 分析日志页：导入 iOS「分析数据」中的 Analytics 日志 → 解析 → 分区块展示。
///
/// 两个区块刻意分开：
/// - **原生字段**：iOS 日志里实际写入的值，可信度高
/// - **衍生指标**：由原生字段推算，口径因 App 而异，故同时展示计算公式
struct AnalyticsView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    /// 主入口：点「导入」直接弹文件管理器，一步到位，不再有中间表单
    @State private var showingFileImporter = false
    /// 次要入口：不方便存文件时才用
    @State private var showingPaste = false
    @State private var showingGuide = false
    @State private var showingReport = false
    @State private var showingResult = false
    @State private var showingRawLog: AnalyticsRecord?

    var body: some View {
        NavigationStack {
            Group {
                if vm.analyticsRecords.isEmpty {
                    emptyState
                } else {
                    List {
                        if let latest = vm.latestAnalytics {
                            Section {
                                recordHeader(latest)
                            }
                        }
                        nativeSection
                        derivedSection
                        if vm.analyticsRecords.count >= 2 {
                            Section("容量趋势") { chart }
                        }
                        historySection
                    }
                }
            }
            .navigationTitle("日志分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showingGuide = true } label: {
                            Label("怎么找到日志", systemImage: "questionmark.circle")
                        }
                        Button { showingPaste = true } label: {
                            Label("粘贴日志文本", systemImage: "doc.on.clipboard")
                        }
                        Button { showingReport = true } label: {
                            Label("周期报告", systemImage: "calendar")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingFileImporter = true } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .disabled(vm.isImporting)
                }
            }
            // 直接从最顶层 VC 弹系统选择器，不经过中间 sheet（避免先闪一层白卡）
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
            .sheet(isPresented: $showingPaste) {
                PasteImportSheet(isPresented: $showingPaste) { showingResult = true }
            }
            .sheet(item: $showingRawLog) { record in rawSheet(record) }
            .sheet(isPresented: $showingReport) {
                BatteryReportView()
            }
            .sheet(isPresented: $showingGuide) {
                NavigationStack {
                    AnalyticsGuideContent()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showingGuide = false }
                            }
                        }
                }
            }
            .alert("导入结果", isPresented: $showingResult) {
                Button("好", role: .cancel) { }
            } message: {
                Text(vm.importMessage ?? "")
            }
            .overlay {
                if vm.isImporting { ParsingOverlay(stage: vm.importStage) }
            }
        }
    }

    // MARK: - 记录头

    private func recordHeader(_ r: AnalyticsRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("最新记录").font(.subheadline).foregroundStyle(.secondary)
                Text(r.dateText).font(.headline)
            }
            Spacer()
            Button {
                showingRawLog = r
            } label: {
                Text("原始").font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 原生字段区块

    private var nativeSection: some View {
        Section {
            if vm.nativeMetrics.isEmpty {
                Text("该记录未包含原生电池字段").foregroundStyle(.secondary).font(.footnote)
            } else {
                ForEach(vm.nativeMetrics) { m in
                    metricRow(m, tint: .blue)
                }
            }
        } header: {
            Label("系统原生数据", systemImage: "checkmark.seal.fill")
        } footer: {
            Text("由 iOS 直接写入分析日志，未经任何推算，可信度高。每项「口径」括号里"
                 + "是它在日志中的真实键名，键名因机型 / 系统版本而异。\n"
                 + "仅展示已解读的实用字段，含义未公开的原始键值不再呈现。")
        }
    }

    // MARK: - 衍生指标区块

    private var derivedSection: some View {
        Section {
            if vm.derivedMetrics.isEmpty {
                Text("数据不足以推算衍生指标。至少需要同时解析出「当前实际容量」与「出厂容量」。")
                    .foregroundStyle(.secondary).font(.footnote)
            } else {
                ForEach(vm.derivedMetrics) { m in
                    metricRow(m, tint: .purple)
                }
            }
        } header: {
            Label("衍生分析指标", systemImage: "function")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("由原生字段推算得出。这些指标不是 iOS 官方定义，不同 App 口径可能不同，请结合每项的「计算口径」自行判断。")
                DisclosureGroup("为什么没有「衰减稳定性 / 电芯一致性」？") {
                    Text("部分第三方工具会给出这两项，但其口径依赖日志中更多未公开字段（如 AppleRawMaxCapacity、Qmax、WeightedRa），仅凭出厂容量与实际容量无法唯一确定。强行拟合会得到看似合理却无依据的数字，因此本 App 不提供，只输出定义明确、可复现的指标。")
                        .font(.caption2)
                }
                .font(.caption)
            }
        }
    }

    private func metricRow(_ m: DerivedMetric, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(m.title, systemImage: m.icon)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(tint)
                Spacer()
                Text(m.valueText)
                    .font(.headline)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("口径：\(m.formula)")
                Text("依据：\(m.basis)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 趋势图

    /// 图上的一个点：日期 + 健康度百分比
    /// 优先用系统写入的 MaximumCapacityPercent；没有时退回「出厂容量 ÷ 额定容量」
    private var healthPoints: [HealthPoint] {
        vm.analyticsRecords.compactMap { r -> HealthPoint? in
            if let h = r.systemHealthPercent {
                return HealthPoint(date: r.date, pct: h)
            }
            guard let n = r.nominalChargeCapacity,
                  let d = r.designCapacity, d > 0 else { return nil }
            return HealthPoint(date: r.date, pct: Double(n) / Double(d) * 100)
        }
    }

    /// Y 轴范围随实际数据浮动，避免 101.72% 这类超出 100% 的值被裁掉
    private var healthDomain: ClosedRange<Double> {
        guard !healthPoints.isEmpty else { return 70...110 }
        let values = healthPoints.map(\.pct)
        let low = min(values.min() ?? 80, 80) - 5
        let high = max(values.max() ?? 100, 100) + 5
        return low...high
    }

    private var chart: some View {
        Chart {
            ForEach(healthPoints) { p in
                LineMark(x: .value("日期", p.date), y: .value("计算健康度", p.pct))
                    .foregroundStyle(.purple)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("日期", p.date), y: .value("计算健康度", p.pct))
                    .foregroundStyle(.purple)
            }
            RuleMark(y: .value("更换阈值", 80.0))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(StrokeStyle(dash: [4, 3]))
        }
        .chartYScale(domain: healthDomain)
        .frame(height: 180)
    }

    // MARK: - 历史

    private var historySection: some View {
        Section("导入记录（\(vm.analyticsRecords.count) 条）") {
            ForEach(vm.analyticsRecords.reversed()) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(r.dateText).font(.subheadline)
                        Spacer()
                        if let h = r.systemHealthPercent {
                            Text(String(format: "系统 %.1f%%", h))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        if let c = r.cycleCount {
                            Text("循环 \(c)").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let n = r.nominalChargeCapacity {
                            Text("出厂 \(n) mAh").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let v = r.rawMaxCapacity {
                            Text("实时 \(v)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        vm.deleteAnalyticsRecord(r)
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
    }

    // MARK: - 原始日志

    private func rawSheet(_ r: AnalyticsRecord) -> some View {
        NavigationStack {
            ScrollView {
                Text(r.rawSnippet.isEmpty ? "（无原始片段）" : r.rawSnippet)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("原始日志片段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingRawLog = nil }
                }
            }
        }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有导入分析日志").font(.headline)
            Text("iOS 的「分析数据」里保存着系统写入的电池健康原始记录，\n"
                 + "包含系统健康度、循环次数、实际容量等。\n\n"
                 + "由于系统限制，本 App 无法自动读取，需要你导出后导入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showingFileImporter = true } label: {
                Label("选择日志文件", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isImporting)

            Button { showingGuide = true } label: {
                Label("怎么找到日志？", systemImage: "questionmark.circle")
            }
            .font(.footnote)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 粘贴导入（次要入口）

private struct PasteImportSheet: View {
    @EnvironmentObject private var vm: BatteryViewModel
    @Binding var isPresented: Bool
    let onFinish: () -> Void

    @State private var pasteText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $pasteText)
                        .frame(minHeight: 220)
                        .font(.system(.caption, design: .monospaced))
                        .overlay(alignment: .topLeading) {
                            if pasteText.isEmpty {
                                Text("在此粘贴 Analytics 日志内容…")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button {
                        pasteText = UIPasteboard.general.string ?? ""
                    } label: {
                        Label("从剪贴板填入", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("粘贴日志文本")
                } footer: {
                    Text("不方便存文件时用这个：在「分析数据」里打开 Analytics-*.ips → 全选 → 拷贝 → 回到这里粘贴。")
                }
            }
            .navigationTitle("粘贴导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("解析") {
                        Task {
                            if await vm.importAnalyticsLog(pasteText) {
                                isPresented = false
                                onFinish()
                            }
                        }
                    }
                    .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || vm.isImporting)
                }
            }
            .overlay {
                if vm.isImporting { ParsingOverlay(stage: vm.importStage) }
            }
        }
    }
}

// MARK: - 解析中遮罩

/// 解析几十 MB 的日志要几秒，主界面在这期间必须有反馈，
/// 否则看起来就跟"点了没反应 / 黑屏卡死"一样。
private struct ParsingOverlay: View {
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

// MARK: - 获取指引

private struct AnalyticsGuideContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                step("1", "打开分析数据", "设置 → 隐私与安全性 → 分析与改进 → 分析数据")
                step("2", "找到日志文件", "找以 Analytics- 开头的文件（如 Analytics-2026-09-24-080008.ips）。系统每天生成一份，选最新的那个")
                step("3", "存到「文件」App", "点开文件 → 右上角分享 → 「存储到文件」。多存几个不同日期的，趋势图才有意义")
                step("4", "回到本 App 导入", "点右上角「导入」→ 选中刚才存的文件，即可自动解析")

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label("说明", systemImage: "info.circle").font(.headline)
                    Text("本 App 无法直接读取系统分析日志目录（iOS 沙箱限制）。因此需要先导出到「文件」App，再由你授权后导入。")
                    Text("一天的日志里电池统计可能写入多次，导入时同一天只保留字段最完整的一条。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("如何获取日志")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n)
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Circle().fill(.tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
