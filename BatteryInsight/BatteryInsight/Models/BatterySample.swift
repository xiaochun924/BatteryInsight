import Foundation
import UIKit

/// UIDevice.BatteryState 的 Codable 映射（原生枚举不可 Codable）
enum BatteryStateKind: String, Codable {
    case unknown, unplugged, charging, full

    init(_ s: UIDevice.BatteryState) {
        switch s {
        case .unplugged: self = .unplugged
        case .charging:  self = .charging
        case .full:      self = .full
        case .unknown:   self = .unknown
        @unknown default: self = .unknown
        }
    }

    var isCharging: Bool { self == .charging || self == .full }

    var displayName: String {
        switch self {
        case .unplugged: return "未充电"
        case .charging:  return "充电中"
        case .full:      return "已充满"
        case .unknown:   return "未知"
        }
    }

    var symbolName: String {
        switch self {
        case .unplugged: return "battery.50"
        case .charging:  return "battery.100.bolt"
        case .full:      return "battery.100"
        case .unknown:   return "battery.0"
        }
    }
}

enum SampleReason: String, Codable {
    case launch, timer, system, manual, demo
}

/// 一次电池采样：时间 + 电量 + 充电状态 + 触发来源
struct BatterySample: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// 电量 0.0 ~ 1.0（UIDevice.batteryLevel 的原生量纲）
    let level: Double
    let state: BatteryStateKind
    let reason: SampleReason

    init(date: Date = Date(),
         level: Double,
         state: BatteryStateKind,
         reason: SampleReason = .timer) {
        self.id = UUID()
        self.date = date
        self.level = level
        self.state = state
        self.reason = reason
    }

    /// 电量百分比 0~100
    var percent: Double { level * 100 }
}
