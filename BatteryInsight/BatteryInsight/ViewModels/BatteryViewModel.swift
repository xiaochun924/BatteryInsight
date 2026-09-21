import Foundation
import SwiftUI

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

    /// 解析并导入粘贴的日志文本，返回是否成功
    @discardableResult
    func importAnalyticsLog(_ text: String) -> Bool {
        let result = AnalyticsLogParser.parse(text)
        guard !result.isEmpty else {
            importSucceeded = false
            importMessage = result.summary
            return false
        }
        let added = store.mergeAnalytics(result.records)
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
