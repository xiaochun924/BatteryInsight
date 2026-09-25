import Foundation
import SwiftUI

/// 一次分析日志导入的汇总结果。
/// 之所以单独建模而不是只回传 Bool：批量导入时「几个文件成功、几个失败、
/// 几条重复」都需要如实告诉用户，否则静默丢数据会让人以为导入成功了。
struct AnalyticsImportReport: Sendable {
    /// 用户选择的文件数
    var fileCount: Int = 0
    /// 成功读取的文件数
    var readCount: Int = 0
    /// 解析出的记录数
    var recordCount: Int = 0
    /// 实际入库的新增条数
    var addedCount: Int = 0
    /// 逐文件的失败原因（文件读不了、编码不对、过大等）
    var failures: [String] = []
    /// 解析过程中的提示（如某文件不含电池字段）
    var warnings: [String] = []

    /// 是否解析到了电池数据（注意：全部重复也返回 true，由 UI 说明「无新增」）
    var succeeded: Bool { recordCount > 0 }

    var message: String {
        var lines: [String] = []

        if recordCount == 0 {
            lines.append("未解析到电池数据（成功读取 \(readCount)/\(fileCount) 个文件）")
        } else if addedCount > 0 {
            lines.append("解析出 \(recordCount) 条记录，新增 \(addedCount) 条")
            if recordCount > addedCount {
                lines.append("另 \(recordCount - addedCount) 条与已有记录重复，已跳过")
            }
        } else {
            lines.append("解析出 \(recordCount) 条记录，但均已存在（无新增）")
        }

        if !failures.isEmpty { lines.append(contentsOf: failures) }
        if !warnings.isEmpty { lines.append("提示：" + warnings.joined(separator: "；")) }

        return lines.joined(separator: "\n")
    }
}

/// 电池分析主状态机：串联监控器、存储与分析引擎。
@MainActor
final class BatteryViewModel: ObservableObject {
    @Published var level: Double = -1                 // 0.0~1.0，<0 表示当前不可读
    @Published var state: BatteryStateKind = .unknown
    @Published var drainRate: Double?                // %/小时
    @Published var remainingHours: Double?
    @Published var samples: [BatterySample] = []
    @Published var sessions: [ChargingSession] = []
    @Published var healthRecords: [HealthRecord] = []
    @Published var analyticsRecords: [AnalyticsRecord] = []
    @Published var tips: [BatteryTip] = []

    /// 最近一次日志导入的提示信息（供 UI 展示成功/失败）
    @Published var importMessage: String?
    @Published var importSucceeded = false
    /// 正在导入/解析。几十 MB 的日志解析要几秒，不挪到后台会把界面卡成黑屏
    @Published var isImporting = false
    /// 当前阶段文案，配合上面的转圈动画显示
    @Published var importStage: String?

    private let monitor = BatteryMonitor()
    private let store = DataStore.shared

    var hasData: Bool { !samples.isEmpty }
    /// 是否能读到真实电量（模拟器会返回 -1）
    var hasRealLevel: Bool { level >= 0 }
    var levelPercent: Double? { level >= 0 ? level * 100 : nil }
    var stateText: String { state.displayName }
    var isCharging: Bool { state.isCharging }

    init() {
        monitor.onSample = { [weak self] sample in
            Task { @MainActor in self?.handle(sample) }
        }
        monitor.onStateChange = { [weak self] oldState, newState, date in
            Task { @MainActor in self?.handleStateChange(from: oldState, to: newState, at: date) }
        }
        refresh()
        monitor.start()
    }

    func refresh() {
        samples = store.samples
        sessions = store.sessions
        healthRecords = store.healthRecords
        analyticsRecords = store.analyticsRecords
        recalc()
    }

    private func handle(_ sample: BatterySample) {
        level = sample.level
        state = sample.state
        store.addSample(sample)
        if sample.state.isCharging {
            store.updateActiveSessionPeak(level: sample.level)
        }
        refresh()
    }

    /// 充电状态翻转时，开启或结算一次充电会话
    private func handleStateChange(from oldState: BatteryStateKind,
                                   to newState: BatteryStateKind,
                                   at date: Date) {
        let wasCharging = oldState.isCharging
        let nowCharging = newState.isCharging
        if !wasCharging && nowCharging {
            store.startSession(at: date, level: max(level, 0))
        } else if wasCharging && !nowCharging {
            store.endActiveSession(at: date, level: max(level, 0))
        }
        refresh()
    }

    private func recalc() {
        drainRate = BatteryAnalytics.drainRate(samples: samples)
        remainingHours = BatteryAnalytics.estimatedRemainingHours(level: max(level, 0),
                                                                  drainRate: drainRate)
        tips = BatteryAnalytics.generateTips(samples: samples,
                                            sessions: sessions,
                                            health: healthRecords)
    }

    // MARK: - 操作

    func addHealth(capacity: Double, cycles: Int?, note: String?) {
        let record = HealthRecord(maximumCapacity: capacity, cycleCount: cycles, note: note)
        store.addHealthRecord(record)
        refresh()
    }

    func deleteHealth(_ record: HealthRecord) {
        store.deleteHealthRecord(record)
        refresh()
    }

    // MARK: - 分析日志导入

    /// 最新一条分析记录
    var latestAnalytics: AnalyticsRecord? {
        analyticsRecords.max { $0.date < $1.date }
    }

    /// 最新记录的原生字段指标
    var nativeMetrics: [DerivedMetric] {
        guard let r = latestAnalytics else { return [] }
        return DerivedMetrics.nativeMetrics(from: r)
    }

    /// 全部记录推导出的衍生指标
    var derivedMetrics: [DerivedMetric] {
        DerivedMetrics.make(from: analyticsRecords)
    }

    /// 解析并导入粘贴的日志文本，返回是否成功。
    ///
    /// 解析放在后台线程：几十 MB 的日志在主线程解析要几秒，界面会直接卡成黑屏，
    /// 期间由 `isImporting` 驱动转圈动画。
    @discardableResult
    func importAnalyticsLog(_ text: String) async -> Bool {
        isImporting = true
        importStage = "正在解析…"
        defer { isImporting = false; importStage = nil }

        let result = await Task.detached(priority: .userInitiated) {
            AnalyticsLogParser.parse(text)
        }.value

        guard !result.isEmpty else {
            importSucceeded = false
            importMessage = result.summary
            return false
        }
        let added = store.mergeAnalytics(result.records)
        syncHealthFromAnalytics(result.records)
        refresh()
        importSucceeded = true
        var msg = "解析出 \(result.records.count) 条记录"
        msg += added > 0 ? "，新增 \(added) 条" : "，均已存在（无新增）"
        if !result.warnings.isEmpty {
            msg += "\n提示：" + result.warnings.joined(separator: "；")
        }
        importMessage = msg
        return true
    }

    /// 从「文件」选中的一个或多个日志导入。
    ///
    /// 逐个文件读取并解析：单个文件读取失败（非文本 / 过大 / 无权限）只记入
    /// `report.failures`，不影响其余文件，最后一次性合并入库。
    @discardableResult
    func importAnalyticsFiles(_ urls: [URL]) async -> AnalyticsImportReport {
        isImporting = true
        importStage = stageText(for: urls)
        defer { isImporting = false; importStage = nil }

        // 读文件 + 解析都在后台跑，主线程只负责转圈动画
        let (scanned, records) = await Task.detached(priority: .userInitiated) {
            () -> (AnalyticsImportReport, [AnalyticsRecord]) in
            var report = AnalyticsImportReport(fileCount: urls.count)
            var records: [AnalyticsRecord] = []
            var warnings: [String] = []

            for url in urls {
                switch AnalyticsFileImporter.readText(of: url) {
                case .failure(let reason):
                    report.failures.append(reason.message)
                case .success(let text):
                    report.readCount += 1
                    let result = AnalyticsLogParser.parse(text)
                    records.append(contentsOf: result.records)
                    // 多文件导入时给提示加上文件名，便于定位是哪个文件没数据
                    if result.records.isEmpty {
                        warnings.append("\(url.lastPathComponent) 未含电池字段")
                        warnings.append(contentsOf: result.warnings)
                    }
                }
            }

            report.recordCount = records.count
            report.warnings = warnings
            return (report, records)
        }.value

        var report = scanned
        report.addedCount = records.isEmpty ? 0 : store.mergeAnalytics(records)
        syncHealthFromAnalytics(records)
        refresh()

        importSucceeded = report.succeeded
        importMessage = report.message
        return report
    }

    // MARK: - 同步到主页

    /// 把日志里读到的健康度也写成一条「健康记录」，让主页面直接看到。
    ///
    /// 之前导入完只写进 `analyticsRecords`，主页依旧是空的，
    /// 从用户角度看跟"导入失败"没区别。同一天只写一条，重复导入不会刷出一堆点。
    private func syncHealthFromAnalytics(_ records: [AnalyticsRecord]) {
        let calendar = Calendar.current
        for r in records {
            guard let capacity = healthPercent(of: r) else { continue }
            let duplicated = store.healthRecords.contains {
                calendar.isDate($0.date, inSameDayAs: r.date)
            }
            guard !duplicated else { continue }
            store.addHealthRecord(HealthRecord(date: r.date,
                                               maximumCapacity: capacity,
                                               cycleCount: r.cycleCount,
                                               note: "来自分析日志"))
        }
    }

    /// 优先用系统写入的健康度；日志没写就用「实际容量 ÷ 出厂容量」算一个
    private func healthPercent(of r: AnalyticsRecord) -> Double? {
        if let h = r.systemHealthPercent { return h }
        guard let nominal = r.nominalChargeCapacity,
              let design = r.designCapacity, design > 0 else { return nil }
        return Double(nominal) / Double(design) * 100
    }

    /// 进度文案带上体积，让用户知道大文件需要等一会儿
    private func stageText(for urls: [URL]) -> String {
        let total = urls.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        guard total > 0 else { return "正在解析…" }
        let mb = max(1, total / 1024 / 1024)
        return "正在解析 \(mb) MB 日志…"
    }

    /// 记录一次导入失败（供 UI 直接展示，例如文档选择器本身报错）
    func reportImportFailure(_ message: String) {
        importSucceeded = false
        importMessage = message
    }

    func deleteAnalyticsRecord(_ r: AnalyticsRecord) {
        store.deleteAnalyticsRecord(r)
        refresh()
    }

    func loadDemoData() {
        store.loadDemoData()
        refresh()
    }

    func clearAll() {
        store.clearAll()
        refresh()
    }
}
