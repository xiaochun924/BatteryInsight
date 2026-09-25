import Foundation

/// 本地数据存储（demo 使用 UserDefaults + Codable）。
/// 生产环境建议换成 SwiftData / CoreData，采样数据量会随时间持续增长。
///
/// Swift 6：DataStore 是共享单例、所有 `@Published` 状态都在同一隔离域被读写，
/// 唯一调用方 `BatteryViewModel` 是 `@MainActor`，因此整体标记为主线程隔离，
/// 满足严格并发检查且不引入跨线程访问同一份可变数据的问题。
@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published private(set) var samples: [BatterySample] = []
    @Published private(set) var sessions: [ChargingSession] = []
    @Published private(set) var healthRecords: [HealthRecord] = []
    @Published private(set) var analyticsRecords: [AnalyticsRecord] = []

    private let kSamples   = "bi.samples"
    private let kSessions  = "bi.sessions"
    private let kHealth    = "bi.health"
    private let kAnalytics = "bi.analytics"
    /// 采样上限，超出后丢弃最旧数据，避免无限增长
    private let sampleCap = 20000

    private init() { load() }

    // MARK: - 采样

    func addSample(_ s: BatterySample) {
        samples.append(s)
        if samples.count > sampleCap {
            samples.removeFirst(samples.count - sampleCap)
        }
        save()
    }

    // MARK: - 充电会话

    func startSession(at date: Date, level: Double) {
        // 若已有进行中的会话（异常中断遗留），先结算
        if let idx = sessions.firstIndex(where: { $0.isActive }) {
            sessions[idx].endDate = date
            sessions[idx].endLevel = sessions[idx].peakLevel
            sessions[idx].isOvernight = Self.isOvernight(start: sessions[idx].startDate, end: date)
        }
        var s = ChargingSession(startDate: date, startLevel: level)
        s.peakLevel = level
        sessions.append(s)
        save()
    }

    func endActiveSession(at date: Date, level: Double) {
        guard let idx = sessions.firstIndex(where: { $0.isActive }) else { return }
        sessions[idx].endDate = date
        sessions[idx].endLevel = level
        sessions[idx].peakLevel = max(sessions[idx].peakLevel, level)
        sessions[idx].isOvernight = Self.isOvernight(start: sessions[idx].startDate, end: date)
        save()
    }

    /// 充电过程中更新峰值电量（用于会话未完成时的展示）
    func updateActiveSessionPeak(level: Double) {
        guard let idx = sessions.firstIndex(where: { $0.isActive }) else { return }
        if level > sessions[idx].peakLevel {
            sessions[idx].peakLevel = level
        }
    }

    /// 整夜充电判定：时长 ≥ 6 小时，或跨日凌晨时段
    static func isOvernight(start: Date, end: Date) -> Bool {
        let cal = Calendar.current
        let hours = end.timeIntervalSince(start) / 3600
        if hours >= 6 { return true }
        guard cal.component(.day, from: start) != cal.component(.day, from: end) else { return false }
        let startHour = cal.component(.hour, from: start)
        let endHour = cal.component(.hour, from: end)
        return startHour >= 20 || endHour <= 8
    }

    // MARK: - 健康度

    func addHealthRecord(_ r: HealthRecord) {
        healthRecords.append(r)
        healthRecords.sort { $0.date < $1.date }
        save()
    }

    func deleteHealthRecord(_ r: HealthRecord) {
        healthRecords.removeAll { $0.id == r.id }
        save()
    }

    // MARK: - 分析日志记录

    /// 合并导入的分析记录：按「日期 + 系统健康度」去重，返回新增条数
    @discardableResult
    func mergeAnalytics(_ incoming: [AnalyticsRecord]) -> Int {
        var existingKeys = Set(analyticsRecords.map(Self.dedupeKey))
        var added = 0
        for r in incoming where !existingKeys.contains(Self.dedupeKey(r)) {
            analyticsRecords.append(r)
            existingKeys.insert(Self.dedupeKey(r))
            added += 1
        }
        analyticsRecords.sort { $0.date < $1.date }
        save()
        return added
    }

    private static func dedupeKey(_ r: AnalyticsRecord) -> String {
        // 同一天 + 同一健康度视为重复（同一次采样重复导入）
        let day = Calendar.current.startOfDay(for: r.date).timeIntervalSince1970
        return "\(Int(day))-\(r.systemHealthPercent.map { String(format: "%.2f", $0) } ?? "-")-\(r.cycleCount ?? -1)"
    }

    /// 整批替换（字段补齐 / 迁移用）：保持日期升序并落盘
    func replaceAnalytics(_ records: [AnalyticsRecord]) {
        analyticsRecords = records.sorted { $0.date < $1.date }
        save()
    }

    // MARK: - 持久化

    private func save() {
        let enc = JSONEncoder()
        if let d = try? enc.encode(samples)         { UserDefaults.standard.set(d, forKey: kSamples) }
        if let d = try? enc.encode(sessions)        { UserDefaults.standard.set(d, forKey: kSessions) }
        if let d = try? enc.encode(healthRecords)   { UserDefaults.standard.set(d, forKey: kHealth) }
        if let d = try? enc.encode(analyticsRecords){ UserDefaults.standard.set(d, forKey: kAnalytics) }
    }

    private func load() {
        let dec = JSONDecoder()
        if let d = UserDefaults.standard.data(forKey: kSamples),
           let arr = try? dec.decode([BatterySample].self, from: d) { samples = arr }
        if let d = UserDefaults.standard.data(forKey: kSessions),
           let arr = try? dec.decode([ChargingSession].self, from: d) { sessions = arr }
        if let d = UserDefaults.standard.data(forKey: kHealth),
           let arr = try? dec.decode([HealthRecord].self, from: d) { healthRecords = arr }
        if let d = UserDefaults.standard.data(forKey: kAnalytics),
           let arr = try? dec.decode([AnalyticsRecord].self, from: d) { analyticsRecords = arr }
    }

    func clearAll() {
        samples = []
        sessions = []
        healthRecords = []
        analyticsRecords = []
        save()
    }

    // MARK: - 演示数据

    /// 生成近 7 天的模拟数据，便于在模拟器（无真实电池数据）中查看完整 UI。
    func loadDemoData() {
        let cal = Calendar.current
        let now = Date()

        var generated: [BatterySample] = []
        for dayOffset in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: now))
            else { continue }
            var level = 1.0
            for hour in stride(from: 8, through: 23, by: 1) {
                guard let t = cal.date(byAdding: .hour, value: hour, to: dayStart) else { continue }
                if t > now { break }
                let state: BatteryStateKind
                if hour >= 23 {
                    state = .charging
                    level = min(1.0, level + 0.28)
                } else {
                    state = .unplugged
                    level = max(0.16, level - 0.058)
                }
                generated.append(BatterySample(date: t, level: level, state: state, reason: .demo))
            }
        }
        samples = generated.sorted { $0.date < $1.date }

        // 模拟几次夜间充电会话
        sessions = []
        for i in 0..<5 {
            guard let day = cal.date(byAdding: .day, value: -(i + 1), to: now),
                  let start = cal.date(bySettingHour: 23, minute: 10, second: 0, of: day)
            else { continue }
            var s = ChargingSession(startDate: start, startLevel: 0.18 + Double(i % 3) * 0.03)
            s.endDate = start.addingTimeInterval(3600 * 2.3)
            s.endLevel = 0.98
            s.peakLevel = 0.98
            s.isOvernight = true
            sessions.append(s)
        }

        // 模拟健康度缓慢衰减
        healthRecords = []
        for i in 0..<6 {
            guard let d = cal.date(byAdding: .month, value: -(5 - i), to: now) else { continue }
            healthRecords.append(
                HealthRecord(date: d,
                             maximumCapacity: 100.0 - Double(i) * 1.9,
                             cycleCount: 120 + i * 38)
            )
        }
        save()
    }
}
