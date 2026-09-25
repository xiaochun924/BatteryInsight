import Foundation
import SwiftUI

/// 周报 / 月报的聚合摘要。
/// 数据全部来自本地已采集 / 已导入的记录，不含推测值；
/// 没有数据的项保持 nil，UI 显示「--」。
struct BatteryReport: Identifiable {
    let id = UUID()
    /// 周期类型
    let kind: String            // 「周报」/「月报」
    /// 周期起止日期
    let startDate: Date
    let endDate: Date

    // 健康度
    let healthStart: Double?    // 周期首条健康度
    let healthEnd: Double?      // 周期末条健康度
    let healthDelta: Double?    // 周期内变化（+ / -）
    // 容量
    let capacityStart: Int?     // 周期首条容量 mAh
    let capacityEnd: Int?       // 周期末条容量 mAh
    let capacityDelta: Int?
    // 循环
    let cyclesStart: Int?
    let cyclesEnd: Int?
    let cyclesDelta: Int?
    // 充电统计
    let chargeCount: Int
    let avgChargeHours: Double?
    let avgChargeSpeed: Double?
    let overnightCount: Int
    // 温度
    let avgTemp: Double?
    let maxTemp: Double?

    /// 周期长度文案，如「9月18日 – 9月24日」
    var rangeText: String {
        startDate.chineseDateText + " – " + endDate.chineseDateText
    }
}

enum BatteryAnalytics {

    // MARK: - 周期报告（周报 / 月报）

    /// 生成最近一个周期的周报 / 月报。
    ///
    /// - kind: 传入「周报」/「月报」；「周报」取近 7 天，「月报」取近 30 天。
    static func makeReport(kind: String,
                           health: [HealthRecord],
                           analytics: [AnalyticsRecord],
                           samples: [BatterySample],
                           sessions: [ChargingSession]) -> BatteryReport {
        let calendar = Calendar.current
        let now = Date()
        let isWeekly = (kind == "周报")
        let days = isWeekly ? 7 : 30
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else {
            return BatteryReport(kind: kind,
                                 startDate: now,
                                 endDate: now,
                                 healthStart: nil, healthEnd: nil, healthDelta: nil,
                                 capacityStart: nil, capacityEnd: nil, capacityDelta: nil,
                                 cyclesStart: nil, cyclesEnd: nil, cyclesDelta: nil,
                                 chargeCount: 0,
                                 avgChargeHours: nil, avgChargeSpeed: nil,
                                 overnightCount: 0,
                                 avgTemp: nil, maxTemp: nil)
        }
        let end = now

        // 健康度：取周期内的首末条
        let healthInRange = health
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
        let healthStart = healthInRange.first?.maximumCapacity
        let healthEnd = healthInRange.last?.maximumCapacity
        let healthDelta = (healthStart != nil && healthEnd != nil)
            ? healthEnd! - healthStart! : nil

        // 容量：来自分析日志 NominalChargeCapacity，按天去重取周期首末
        let capInRange = analytics
            .filter { $0.date >= start && $0.date <= end && $0.nominalChargeCapacity != nil }
            .sorted { $0.date < $1.date }
        let capStart = capInRange.first?.nominalChargeCapacity
        let capEnd = capInRange.last?.nominalChargeCapacity
        let capDelta = (capStart != nil && capEnd != nil)
            ? capEnd! - capStart! : nil

        // 循环：取周期首末条的循环次数
        let cyclesInRange = analytics
            .filter { $0.date >= start && $0.date <= end && $0.cycleCount != nil }
            .sorted { $0.date < $1.date }
        let cyclesStart = cyclesInRange.first?.cycleCount
        let cyclesEnd = cyclesInRange.last?.cycleCount
        let cyclesDelta = (cyclesStart != nil && cyclesEnd != nil)
            ? cyclesEnd! - cyclesStart! : nil

        // 充电会话：周期内开启的
        let chargeSessions = sessions.filter { $0.startDate >= start && $0.startDate <= end }
        let done = chargeSessions.filter { !$0.isActive }
        let avgHours = done.isEmpty ? nil : done.map { $0.duration / 3600 }.reduce(0, +) / Double(done.count)
        let speeds = chargeSessions.compactMap { $0.speedPercentPerHour }
        let avgSpeed = speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)

        // 温度：周期内分析日志的 maxTemperature（0.1℃ 已换算）均值与峰值
        let temps = analytics.filter { $0.date >= start && $0.date <= end && $0.maxTemperature != nil }
            .compactMap { $0.maxTemperature }
        let avgTemp = temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count)
        let maxTemp = temps.max()

        return BatteryReport(
            kind: kind,
            startDate: start,
            endDate: end,
            healthStart: healthStart,
            healthEnd: healthEnd,
            healthDelta: healthDelta,
            capacityStart: capStart,
            capacityEnd: capEnd,
            capacityDelta: capDelta,
            cyclesStart: cyclesStart,
            cyclesEnd: cyclesEnd,
            cyclesDelta: cyclesDelta,
            chargeCount: chargeSessions.count,
            avgChargeHours: avgHours,
            avgChargeSpeed: avgSpeed,
            overnightCount: chargeSessions.filter { $0.isOvernight }.count,
            avgTemp: avgTemp,
            maxTemp: maxTemp)
    }

    // MARK: - 耗电速率

    /// 估算当前耗电速率（%/小时）：取最近若干小时内未充电采样点的首尾差值
    static func drainRate(samples: [BatterySample], withinHours: Double = 6) -> Double? {
        let cutoff = Date().addingTimeInterval(-withinHours * 3600)
        let points = samples
            .filter { $0.date >= cutoff && $0.state == .unplugged }
            .sorted { $0.date < $1.date }
        guard let first = points.first, let last = points.last else { return nil }
        let hours = last.date.timeIntervalSince(first.date) / 3600
        // 间隔太短算出来的速率不可信
        guard hours >= 0.05 else { return nil }
        let diff = first.level - last.level
        guard diff > 0 else { return nil }
        return diff * 100 / hours
    }

    /// 按当前速率预估剩余可用小时数
    static func estimatedRemainingHours(level: Double, drainRate: Double?) -> Double? {
        guard let rate = drainRate, rate > 0, level > 0 else { return nil }
        return level * 100 / rate
    }

    static func todaySamples(_ samples: [BatterySample]) -> [BatterySample] {
        let start = Calendar.current.startOfDay(for: Date())
        return samples.filter { $0.date >= start }.sorted { $0.date < $1.date }
    }

    /// 今日已消耗电量（百分点）
    static func todayDrainPercent(_ samples: [BatterySample]) -> Double? {
        let points = todaySamples(samples).filter { $0.state == .unplugged }
        guard let first = points.first, let last = points.last, last.date > first.date else { return nil }
        let diff = first.level - last.level
        return diff > 0 ? diff * 100 : nil
    }

    // MARK: - 充电统计

    static func todayChargeCount(sessions: [ChargingSession]) -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        return sessions.filter { $0.startDate >= start }.count
    }

    /// 平均充电时长（小时），仅统计已结束会话
    static func averageChargeHours(sessions: [ChargingSession]) -> Double? {
        let done = sessions.filter { !$0.isActive }
        guard !done.isEmpty else { return nil }
        return done.map { $0.duration / 3600 }.reduce(0, +) / Double(done.count)
    }

    /// 平均充电速度（%/小时）
    static func averageChargeSpeed(sessions: [ChargingSession]) -> Double? {
        let valid = sessions.compactMap { $0.speedPercentPerHour }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    static func overnightCount(sessions: [ChargingSession]) -> Int {
        sessions.filter { $0.isOvernight }.count
    }

    // MARK: - 健康度

    static func latestHealth(_ records: [HealthRecord]) -> HealthRecord? {
        records.sorted { $0.date < $1.date }.last
    }

    /// 健康度衰减速率（%/月），基于最早与最新记录线性估算
    static func healthDeclinePerMonth(_ records: [HealthRecord]) -> Double? {
        let sorted = records.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last, last.date > first.date else { return nil }
        let months = last.date.timeIntervalSince(first.date) / (30 * 24 * 3600)
        guard months > 0 else { return nil }
        let diff = first.maximumCapacity - last.maximumCapacity
        guard diff >= 0 else { return nil }
        return diff / months
    }

    /// 按当前衰减速率，估算容量降到 80% 还需多少个月
    static func monthsUntil80(records: [HealthRecord]) -> Double? {
        guard let latest = latestHealth(records),
              let rate = healthDeclinePerMonth(records),
              rate > 0,
              latest.maximumCapacity > 80 else { return nil }
        return (latest.maximumCapacity - 80) / rate
    }
}
