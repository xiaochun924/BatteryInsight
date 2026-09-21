import Foundation

enum HAClientError: LocalizedError {
    case invalidURL
    case unauthorized
    case server(status: Int, body: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "实例地址无效，请检查 URL"
        case .unauthorized:          return "令牌无效或未授权（401），请重新生成长期访问令牌"
        case .server(let s, let b):  return "服务器返回 \(s)：\(b)"
        case .decoding(let e):       return "数据解析失败：\(e.localizedDescription)"
        }
    }
}

/// 忽略自签名证书错误的会话代理（仅当设置开启时使用）。
final class HAURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

/// Home Assistant REST API 客户端，基于 async/await。
actor HAClient {
    let baseURL: URL
    let token: String
    private let session: URLSession

    init(settings: ConnectionSettings) throws {
        let trimmed = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            throw HAClientError.invalidURL
        }
        self.baseURL = url
        self.token = settings.token

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        if settings.ignoreSSL {
            self.session = URLSession(configuration: config,
                                      delegate: HAURLSessionDelegate(),
                                      delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: config)
        }
    }

    /// 兼容 HA 带微秒的时间戳（如 2024-01-01T12:00:00.123456+00:00）
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
            if let date = f.date(from: s) { return date }
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath,
                                                     debugDescription: "无法解析日期: \(s)"))
        }
        return d
    }

    private func request(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw HAClientError.server(status: 0, body: "未收到 HTTP 响应")
        }
        if http.statusCode == 401 { throw HAClientError.unauthorized }
        if !(200...299).contains(http.statusCode) {
            throw HAClientError.server(status: http.statusCode,
                                       body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// GET /api/states —— 拉取全部实体状态
    func fetchStates() async throws -> [HAEntity] {
        let data = try await request(path: "api/states")
        return try decoder().decode([HAEntity].self, from: data)
    }

    /// POST /api/services/{domain}/{service} —— 调用服务
    func callService(domain: String, service: String, entityId: String) async throws {
        let payload = ["entity_id": entityId]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request(path: "api/services/\(domain)/\(service)", method: "POST", body: body)
    }

    /// 切换开关类实体（按 domain 选择正确服务名）
    func toggle(_ entity: HAEntity) async throws {
        let service: String
        switch entity.domain {
        case "lock":                         // 锁：locked / unlocked
            service = entity.isOn ? "unlock" : "lock"
        case "cover":                        // 窗帘：open / closed
            service = entity.isOn ? "close_cover" : "open_cover"
        case "media_player":                 // 媒体：playing / paused
            service = entity.isOn ? "media_pause" : "media_play"
        default:                             // light / switch / fan 等
            service = entity.isOn ? "turn_off" : "turn_on"
        }
        try await callService(domain: entity.domain, service: service, entityId: entity.entityId)
    }
}
