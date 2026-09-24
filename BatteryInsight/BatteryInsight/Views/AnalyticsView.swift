import SwiftUI
import Charts
import UIKit

/// 分析日志页：导入 iOS「分析数据」中的 Analytics 日志 → 解析 → 分区块展示。
///
/// 两种导入方式：
/// - **选文件**（推荐）：在「分析数据」里把 .ips 存到「文件」App，再在这里选中，可多选
/// - **粘贴文本**：兜底方案，适合只有片段、或不方便存文件的场景
///
/// 两个区块刻意分开：
/// - **原生字段**：iOS 日志里实际写入的值，可信度高
/// - **衍生指标**：由原生字段推算，口径因 App 而异，故同时展示计算公式
/// 容量趋势图上的一个数据点
private struct HealthPoint: Identifiable {
    let id = UUID()
    let date: Date
    let pct: Double
}

struct AnalyticsView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    @State private var showingImport = false
    @State private var pasteText = ""
    @State private var showingRawLog: AnalyticsRecord?
    @State private var showingGuide = false
    @State private var showingFileImporter = false

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
                    Button { showingGuide = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImport = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showingImport) { importSheet }
            .sheet(item: $showingRawLog) { record in rawSheet(record) }
            .sheet(isPresented: $showingGuide) { guideSheet }
            // 系统文档选择器：读取「文件」App / 隔空投送 / 云盘里的日志
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: AnalyticsFileImporter.allowedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                // 取消选择属于正常操作，静默返回，不打扰用户
                guard case .success(let urls) = result else { return }
                let report = vm.importAnalyticsFiles(urls)
                if !report.succeeded {
                    // 失败时打开导入页，借用其中的结果区展示逐文件原因
                    showingImport = true
                }
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
            Text("由 iOS 直接写入分析日志，未经任何推算，可信度高。")
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

    /// 图上的一个点：日期 + 由「实际容量 ÷ 出厂容量」算出的百分比
    private var healthPoints: [HealthPoint] {
        vm.analyticsRecords.compactMap { r -> HealthPoint? in
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
                            Text(String(format: "系统 %.2f%%", h))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        if let c = r.cycleCount {
                            Text("循环 \(c)").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let n = r.nominalChargeCapacity {
                            Text("容量 \(n) mAh").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let d = r.designCapacity {
                            Text("出厂 \(d)").font(.caption2).foregroundStyle(.secondary)
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

    // MARK: - 导入弹窗

    private var importSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("选择日志文件", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } header: {
                    Text("方式一：从文件导入（推荐）")
                } footer: {
                    Text("先在「分析数据」里把 Analytics-*.ips 分享并存储到「文件」App（或用隔空投送到本机），再在这里选中。可一次选多个文件批量导入，不会漏内容。")
                }

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
                    Text("方式二：粘贴文本")
                } footer: {
                    Text("不方便存文件时用这个：在「分析数据」里打开 Analytics-*.ips → 全选 → 拷贝 → 回到这里粘贴。只需含 batteryhealth 字段的片段即可。")
                }

                if let msg = vm.importMessage {
                    Section("解析结果") {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(vm.importSucceeded ? .green : .orange)
                    }
                }

                Section {
                    Button {
                        if vm.importAnalyticsLog(pasteText) {
                            pasteText = ""
                        }
                    } label: {
                        Label("解析并导入", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        showingImport = false
                        showingGuide = true
                    } label: {
                        Label("怎么找到这些日志？", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("导入分析日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingImport = false }
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

    // MARK: - 指引

    private var guideSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    step("1", "打开分析数据", "设置 → 隐私与安全性 → 分析与改进 → 分析数据")
                    step("2", "找到日志文件", "列表里找以 Analytics- 开头的 .ips 文件（如 Analytics-2026-09-19-100000.ips），按日期排序，选最新的一条")
                    step("3", "存到「文件」App（推荐）", "点开文件 → 右上角分享 → 「存储到文件」，挑个位置存下。多存几个不同日期的，趋势图才有意义")
                    step("4", "回到本 App 导入", "点右上角导入按钮 → 「选择日志文件」→ 选中刚才存的文件。也可以在第 3 步直接全选复制文本，走「粘贴文本」")

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Label("说明", systemImage: "info.circle").font(.headline)
                        Text("本 App 无法直接读取系统分析日志目录（iOS 沙箱限制，第三方 App 无权限访问）。因此需要你先导出到「文件」App，再由你授权后导入。")
                        Text("日志中的 batteryhealth 段落并非每次采样都写入，通常几小时到一天出现一次，所以导入多条才能看到趋势。")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("如何获取日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingGuide = false }
                }
            }
        }
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

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有导入分析日志").font(.headline)
            Text("iOS 的「分析数据」里保存着系统写入的电池健康原始记录，\n包含系统健康度、循环次数、实际容量等。\n\n由于系统限制，本 App 无法自动读取，需要你导出后导入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("选择文件", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingImport = true
                } label: {
                    Label("粘贴文本", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Button {
                    showingGuide = true
                } label: {
                    Label("怎么找", systemImage: "questionmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
