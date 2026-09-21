import Foundation
import SwiftUI

/// 一条省电/保养建议
struct BatteryTip: Identifiable {
    enum Severity { case info, warning, critical }

    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let severity: Severity

    var tint: Color {
        switch severity {
        case .info:     return .blue
        case .warning:  return .orange
        case .critical: return .red
        }
    }
}

enum BatteryAnalytics {

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

    /// 是否存在「充满后仍长时间连接」的会话
    static func hasLongFullCharge(sessions: [ChargingSession], thresholdHours: Double = 3) -> Bool {
        sessions.contains { session in
            session.peakLevel >= 0.99 && session.duration / 3600 >= thresholdHours
        }
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

    // MARK: - 建议生成

    static func generateTips(samples: [BatterySample],
                             sessions: [ChargingSession],
                             health: [HealthRecord]) -> [BatteryTip] {
        var tips: [BatteryTip] = []

        // 1. 整夜充电
        let overnight = overnightCount(sessions: sessions)
        if overnight >= 3 {
            tips.append(BatteryTip(
                icon: "moon.zzz.fill",
                title: "检测到 \(overnight) 次整夜充电",
                detail: "长期整夜满电会加速电池老化。建议在「设置 → 电池 → 电池健康」开启「优化电池充电」，让系统学习你的作息并暂缓充至 80% 以上。",
                severity: .warning))
        }

        // 2. 充满后长时间连接
        if hasLongFullCharge(sessions: sessions) {
            tips.append(BatteryTip(
                icon: "bolt.badge.clock",
                title: "存在满电后长时间连接",
                detail: "电池充满后继续插着电源会让电池持续处于高压状态。充满后建议及时拔掉，尤其避免整夜插电。",
                severity: .warning))
        }

        // 3. 健康度阈值
        if let latest = latestHealth(health) {
            if latest.maximumCapacity < 80 {
                tips.append(BatteryTip(
                    icon: "exclamationmark.triangle.fill",
                    title: "最大容量已降至 \(String(format: "%.0f", latest.maximumCapacity))%",
                    detail: "已低于 Apple 建议的 80% 阈值，电池续航会明显下降。建议预约官方更换电池。",
                    severity: .critical))
            } else if latest.maximumCapacity < 85 {
                tips.append(BatteryTip(
                    icon: "battery.75",
                    title: "最大容量 \(String(format: "%.0f", latest.maximumCapacity))%，接近更换阈值",
                    detail: "距离 80% 的更换建议线已不远，可以开始规划更换时机。",
                    severity: .warning))
            }
        }

        // 4. 耗电速率
        if let rate = drainRate(samples: samples), rate > 15 {
            tips.append(BatteryTip(
                icon: "flame.fill",
                title: "当前耗电偏快（约 \(String(format: "%.1f", rate))%/小时）",
                detail: "可检查：后台 App 刷新、定位常驻、屏幕亮度过高、信号弱区驻留、或近期是否有异常耗电的 App。",
                severity: .warning))
        }

        // 5. 深度放电
        let deepDischarge = sessions.filter { $0.startLevel < 0.1 }.count
        if deepDischarge >= 2 {
            tips.append(BatteryTip(
                icon: "battery.25",
                title: "有 \(deepDischarge) 次在电量低于 10% 才开始充电",
                detail: "锂电池不宜深度放电。尽量在 20%~30% 时补电，保持「浅充浅放」更利于延长寿命。",
                severity: .warning))
        }

        // 6. 常驻通用建议
        tips.append(BatteryTip(
            icon: "thermometer.sun.fill",
            title: "避免高温环境充电",
            detail: "高温是电池老化的最大元凶。充电时避免阳光直射、避免边玩大型游戏边充，发热明显时可取下保护壳。",
            severity: .info))
        tips.append(BatteryTip(
            icon: "cable.connector",
            title: "使用原装或 MFi 认证充电器",
            detail: "劣质充电器电压电流不稳，可能损伤电池与充电电路。",
            severity: .info))
        tips.append(BatteryTip(
            icon: "chart.line.downtrend.xyaxis",
            title: "长期存放请保持约 50% 电量",
            detail: "若设备长期不用，充到一半再关机存放，比满电或空电存放更能保护电池。",
            severity: .info))

        return tips
    }
}
