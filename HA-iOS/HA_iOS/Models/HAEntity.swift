import Foundation

/// Home Assistant 实体属性值是异构 JSON，这里用 enum 覆盖常见类型。
// Swift 6：值类型跨 actor/任务边界传递需显式声明 Sendable
enum HAAttributeValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([HAAttributeValue])
    case object([String: HAAttributeValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        // 注意顺序：bool 要先于 number，否则 true 会被当 Double 的 1.0
        if let v = try? container.decode(Bool.self) {
            self = .bool(v); return
        }
        if let v = try? container.decode(Double.self) {
            self = .number(v); return
        }
        if let v = try? container.decode(String.self) {
            self = .string(v); return
        }
        if let v = try? container.decode([HAAttributeValue].self) {
            self = .array(v); return
        }
        if let v = try? container.decode([String: HAAttributeValue].self) {
            self = .object(v); return
        }
        self = .null
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var doubleValue: Double? {
        if case .number(let d) = self { return d }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

/// 对应 HA `/api/states` 返回的单个实体状态对象。
struct HAEntity: Decodable, Identifiable, Equatable, Sendable {
    let entityId: String
    let state: String
    let attributes: [String: HAAttributeValue]
    let lastChanged: Date?
    let lastUpdated: Date?

    var id: String { entityId }

    /// domain 是 entity_id 中 "." 之前的部分，例如 light / switch / sensor
    var domain: String {
        let parts = entityId.split(separator: ".")
        return parts.isEmpty ? "" : String(parts[0])
    }

    var friendlyName: String {
        attributes["friendly_name"]?.stringValue ?? entityId
    }

    var unit: String? {
        attributes["unit_of_measurement"]?.stringValue
    }

    /// 用于 SwiftUI 的 SF Symbols 图标名
    var iconName: String {
        if let custom = attributes["icon"]?.stringValue, custom.hasPrefix("mdi:") == false {
            return custom
        }
        return defaultIcon
    }

    private var defaultIcon: String {
        switch domain {
        case "light": return "lightbulb"
        case "switch": return "toggle.on.square"
        case "cover": return "arrow.up.arrow.down.square"
        case "sensor", "binary_sensor": return "sensor"
        case "climate": return "thermometer"
        case "fan": return "fan"
        case "lock": return "lock"
        case "media_player": return "speaker.wave.2"
        case "camera": return "video"
        case "weather": return "cloud.sun"
        case "device_tracker": return "location"
        default: return "circle"
        }
    }

    var isOn: Bool {
        ["on", "open", "playing", "home", "locked"].contains(state)
    }

    /// 是否支持开/关类服务调用
    var isToggleable: Bool {
        ["light", "switch", "fan", "lock", "cover", "media_player"].contains(domain)
    }

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }
}
