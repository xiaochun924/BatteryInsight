import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 分析日志（Analytics-*.ips）导入与解读页。
///
/// 数据来源：系统「设置 → 隐私与安全性 → 分析与改进 → 分析数据」，
/// 其中以 `Analytics-` 开头、日期 + 时间命名的 `.ips` 文件带当天聚合的电池统计。
struct AnalyticsView: View {
    @ObservedObject var viewModel: BatteryViewModel
    @State private var showingDocumentPicker = false
    @State private var showingPaste = false
    @State private var showingReport = false
    @State private var reportKind = "周报"

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.analyticsRecords.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("分析日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            Label("导入文件", systemImage: "folder")
                        }
                        Button {
                            showingPaste = true
                        } label: {
                            Label("粘贴文本", systemImage: "doc.text")
                        }
                        Divider()
                        if !viewModel.analyticsRecords.isEmpty {
                            Button {
                                reportKind = "周报"
                                showingReport = true
                            } label: {
                                Label("周报", systemImage: "calendar")
                            }
                            Button {
                                reportKind = "月报"
                                showingReport = true
                            } label: {
                                Label("月报", systemImage: "calendar.badge.clock")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker { urls in
                    guard !urls.isEmpty else { return }
                    Task { await viewModel.importAnalyticsFiles(urls) }
                }
            }
            .sheet(isPresented: $showingPaste) {
                PasteLogView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingReport) {
                BatteryReportView(kind: reportKind, viewModel: viewModel)
            }
            .overlay {
                if viewModel.isImporting {
                    importingOverlay
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let msg = viewModel.importMessage {
                    importBanner
                }
                latestSection
                nativeMetricsSection
                derivedSection
                historySection
            }
            .padding()
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("还没有分析数据")
                .font(.title2.weight(.semibold))
            Text("从系统「设置 → 隐私与安全性 → 分析与改进 → 分析数据」
                选择以 Analytics 开头的 .ips 文件导入，或直接粘贴日志文本。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showingDocumentPicker = true
            } label: {
                Label("选择日志文件", systemImage: "folder")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            if let msg = viewModel.importMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(viewModel.importSucceeded ? .green : .red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: viewModel.importSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(viewModel.importSucceeded ? .green : .red)
            Text(viewModel.importMessage ?? "")
                .font(.subheadline)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(
            (viewModel.importSucceeded ? Color.green : Color.red).opacity(0.1)))
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(viewModel.importStage ?? "正在解析…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
        }
    }

    private var latestSection: some View {
        Group {
            if let latest = viewModel.latestAnalytics {
                SectionCard(title: "最新记录", systemImage: "clock.fill", footer: sourceFooter(latest)) {
                    VStack(spacing: 12) {
                        HStack {
                            Text(latest.dateText)
                                .font(.headline)
                            Spacer()
                            Button {
                                viewModel.deleteAnalyticsRecord(latest)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                        }
                        if let h = latest.systemHealthPercent {
                            valueRow("系统健康度", "\(String(format: "%.1f", h))%", "checkmark.seal")
                        }
                        if let c = latest.cycleCount {
                            valueRow("循环次数", "\(c) 次", "arrow.2.circlepath")
                        }
                        if let n = latest.nominalChargeCapacity {
                            valueRow("出厂容量（标称）", "\(n) mAh", "battery.100")
                        }
                        if let d = latest.designCapacity {
                            valueRow("额定容量（设计）", "\(d) mAh", "shippingbox")
                        }
                    }
                }
            }
        }
    }

    private var nativeMetricsSection: some View {
        Group {
            let metrics = viewModel.nativeMetrics
            if !metrics.isEmpty {
                SectionCard(title: "电池原生数据", systemImage: "battery.100")
                {
                    VStack(spacing: 12) {
                        ForEach(metrics) { m in
                            MetricRow(metric: m)
                        }
                    }
                }
            }
        }
    }

    private var derivedSection: some View {
        Group {
            let metrics = viewModel.derivedMetrics
            if !metrics.isEmpty {
                SectionCard(title: "衍生分析", systemImage: "chart.line.uptrend.xyaxis",
                            footer: "衍生指标基于日志原始字段推算，口径见各项说明。") {
                    VStack(spacing: 12) {
                        ForEach(metrics) { m in
                            MetricRow(metric: m)
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        SectionCard(title: "历史记录", systemImage: "clock.arrow.circlepath",
                    footer: "仅展示已解读的实用字段，含义未公开的原始键值不再呈现。") {
            VStack(spacing: 0) {
                ForEach(viewModel.analyticsRecords.sorted { $0.date > $1.date }) { r in
                    NavigationLink {
                        RecordDetailView(record: r)
                    } label: {
                        historyRow(r)
                    }
                    if r.id != viewModel.analyticsRecords.sorted { $0.date > $1.date }.first?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func historyRow(_ r: AnalyticsRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "battery.100")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.dateText)
                    .font(.subheadline.weight(.medium))
                if let h = r.systemHealthPercent {
                    Text("健康度 \(String(format: "%.1f", h))%").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let c = r.cycleCount {
                Text("\(c) 循环").font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private func valueRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    private func sourceFooter(_ r: AnalyticsRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("iOS 直接写入，键名随机型/系统版本而异").font(.caption)
            if r.date >= Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date() {
                Text("本记录为近 24 小时内数据").font(.caption2).foregroundStyle(.green)
            }
        }
    }
}

/// 单个指标的展示行：图标 + 标题 + 值 + 口径说明
struct MetricRow: View {
    let metric: DerivedMetric

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: metric.icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.subheadline.weight(.medium))
                Text(metric.formula)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(metric.valueText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }
}

/// 通用卡片容器：统一圆角、内边距与标题行
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var footer: String?
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, footer: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// 从系统「文件」中选择一个或多个日志
private struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText, .data, .json])
        controller.allowsMultipleSelection = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
