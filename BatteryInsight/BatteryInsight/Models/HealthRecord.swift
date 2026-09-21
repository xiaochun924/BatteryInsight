import Foundation

/// 电池健康度记录。
/// 说明：iOS 不开放「最大容量 / 循环次数」给第三方 App（私有 API 会被拒审），
/// 因此健康度数据由用户在「设置 → 电池 → 电池健康」查看后手动录入。
struct HealthRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// 最大容量百分比，例如 92.0 表示 92%
    let maximumCapacity: Double
    var cycleCount: Int?
    var note: String?

    init(date: Date = Date(),
         maximumCapacity: Double,
         cycleCount: Int? = nil,
         note: String? = nil) {
        self.id = UUID()
        self.date = date
        self.maximumCapacity = maximumCapacity
        self.cycleCount = cycleCount
        self.note = note
    }

    var dateText: String {
        date.formatted(.dateTime.year().month().day())
    }
}
