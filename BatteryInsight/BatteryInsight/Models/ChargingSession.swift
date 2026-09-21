import Foundation

/// 一次完整充电会话
struct ChargingSession: Codable, Identifiable, Equatable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    let startLevel: Double
    var endLevel: Double?
    var peakLevel: Double
    /// 是否为整夜充电（时长超阈值或跨凌晨）
    var isOvernight: Bool

    init(startDate: Date, startLevel: Double) {
        self.id = UUID()
        self.startDate = startDate
        self.startLevel = startLevel
        self.endDate = nil
        self.endLevel = nil
        self.peakLevel = startLevel
        self.isOvernight = false
    }

    /// 会话时长（秒）；进行中则用当前时间
    var duration: TimeInterval {
        (endDate ?? Date()).timeIntervalSince(startDate)
    }

    var isActive: Bool { endDate == nil }

    /// 充电速度：%/小时
    var speedPercentPerHour: Double? {
        guard let end = endLevel else { return nil }
        let hours = duration / 3600
        guard hours > 0 else { return nil }
        return (end - startLevel) * 100 / hours
    }

    /// 本次充入的百分点
    var gainedPercent: Double {
        ((endLevel ?? peakLevel) - startLevel) * 100
    }

    var durationText: String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h) 小时 \(m) 分" }
        return "\(m) 分钟"
    }

    var startDateText: String {
        startDate.formatted(.dateTime.month().day().hour().minute())
    }
}
