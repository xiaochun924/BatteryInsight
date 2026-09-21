import Foundation

/// 与某个 Home Assistant 实例的连接配置。
struct ConnectionSettings: Codable, Equatable, Sendable {
    /// 实例地址，例如 https://home.example.com 或 http://192.168.1.10:8123
    var baseURL: String
    /// 长期访问令牌（Long-Lived Access Token），在 HA 用户资料页生成
    var token: String
    /// 是否忽略自签名证书错误（HA 常见的自签 https 场景）
    var ignoreSSL: Bool

    static let empty = ConnectionSettings(baseURL: "", token: "", ignoreSSL: false)
}

/// 简单的连接配置存储。
/// 注意：此 demo 使用 UserDefaults 明文保存 token，仅用于演示；
/// 生产环境请把 token 改存 Keychain（见 README）。
// Swift 6：全局共享实例需在并发域中安全访问，UserDefaults 本身线程安全
final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()

    private let key = "com.ha.ios.connection"
    private let ud = UserDefaults.standard

    var settings: ConnectionSettings? {
        get {
            guard let data = ud.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(ConnectionSettings.self, from: data)
        }
        set {
            if let v = newValue, let data = try? JSONEncoder().encode(v) {
                ud.set(data, forKey: key)
            } else {
                ud.removeObject(forKey: key)
            }
        }
    }

    var isConfigured: Bool {
        guard let s = settings else { return false }
        return !s.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !s.token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func save(_ settings: ConnectionSettings) {
        self.settings = settings
    }

    func clear() {
        ud.removeObject(forKey: key)
    }
}
