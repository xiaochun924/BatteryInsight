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
    /// 进行中的充电会话（供充电检测卡展示当前充电进度）
    var activeChargingSession: ChargingSession? {
        sessions.first { $0.isActive }
    }

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
        migrateLegacyAnalyticsIfNeeded()
        recalc()
    }

    // MARK: - 旧记录字段补齐

    /// 迁移标记：只跑一次，避免每次启动都重解析
    private static let migrationKey = "bi.migrated.analytics.v2"

    /// 旧版本落盘的记录只有 健康度/循环/容量，没有满充容量、Qmax、电压、电流等字段，
    /// 用户重装后不重新导入就看不到新内容。这里用落盘的原始片段（rawSnippet）
    /// 跑一遍当前解析器补齐，原记录的其他字段保持不变。
    private func migrateLegacyAnalyticsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.migrationKey)
        guard analyticsRecords.contains(where: { $0.rawMaxCapacity == nil && !$0.rawSnippet.isEmpty })
        else { return }

        let updated = analyticsRecords.map { old -> AnalyticsRecord in
            guard old.rawMaxCapacity == nil, !old.rawSnippet.isEmpty,
                  let fresh = AnalyticsLogParser.parse(old.rawSnippet).records.first
            else { return old }
            return Self.merged(old, fresh)
        }
        store.replaceAnalytics(updated)
        analyticsRecords = updated
    }

    /// 旧记录保留原有字段，只把新解析出来的字段补进去
    private static func merged(_ old: AnalyticsRecord, _ fresh: AnalyticsRecord) -> AnalyticsRecord {
        AnalyticsRecord(
            id: old.id,
            date: old.date,
            systemHealthPercent: old.systemHealthPercent ?? fresh.systemHealthPercent,
            cycleCount: old.cycleCount ?? fresh.cycleCount,
            nominalChargeCapacity: old.nominalChargeCapacity ?? fresh.nominalChargeCapacity,
            designCapacity: old.designCapacity ?? fresh.designCapacity,
            rawMaxCapacity: fresh.rawMaxCapacity,
            minFCC: fresh.minFCC,
            maxFCC: fresh.maxFCC,
            minQmax: fresh.minQmax,
            maxQmax: fresh.maxQmax,
            qmaxCell0: fresh.qmaxCell0,
            minPackVoltage: fresh.minPackVoltage,
            maxPackVoltage: fresh.maxPackVoltage,
            maxChargeCurrent: fresh.maxChargeCurrent,
            maxDischargeCurrent: fresh.maxDischargeCurrent,
            minTemperature: fresh.minTemperature,
            maxTemperature: fresh.maxTemperature,
            dailyMinSoc: fresh.dailyMinSoc,
            dailyMaxSoc: fresh.dailyMaxSoc,
            totalOperatingHours: fresh.totalOperatingHours,
            lastUpdateTime: fresh.lastUpdateTime,
            firstUseDate: old.firstUseDate ?? fresh.firstUseDate,
            batterySerialChanged: old.batterySerialChanged ?? fresh.batterySerialChanged,
            voltage: old.voltage ?? fresh.voltage,
            temperature: old.temperature ?? fresh.temperature,
            rawSnippet: old.rawSnippet,
            extraFields: old.extraFields,
            fieldSources: old.fieldSources)
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
    }

    // MARK: - 操作

    func deleteHealth(_ record: HealthRecord) {
        store.deleteHealthRecord(record)
        refresh()
    }

    // MARK: - 分析日志导入

    /// 最新一条分析记录
    var latestAnalytics: AnalyticsRecord? {
        analyticsRecords.max { $0.date < $1.date }
    }

    /// 解析并导入从「文件」选中的一个或多个日志。
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
    /// 健康度一律用「自己计算」的口径（见 healthPercent），不写系统值。
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

    /// 健康度一律用「自己计算」的口径：额定容量 ÷ 出厂容量 × 100%。
    /// 出厂容量优先取日志 DesignCapacity（旧格式），iOS 26 日志缺失时按机型查官方标称。
    /// 不再使用系统写入的 MaximumCapacityPercent。
    private func healthPercent(of r: AnalyticsRecord) -> Double? {
        guard let nominal = r.nominalChargeCapacity else { return nil }
        let design = r.designCapacity ?? DeviceBatterySpec.current?.factoryCapacity
        guard let design, design > 0 else { return nil }
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

    func loadDemoData() {
        store.loadDemoData()
        refresh()
    }

    func clearAll() {
        store.clearAll()
        refresh()
    }
}
