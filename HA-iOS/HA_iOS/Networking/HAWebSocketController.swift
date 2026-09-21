import Foundation

/// 通过 WebSocket 订阅 Home Assistant 的 `state_changed` 事件，实现状态实时刷新。
///
/// 协议流程：
/// 1. 连接 `ws(s)://host/api/websocket`
/// 2. 收到 `auth_required` 后发送 `{"type":"auth","access_token":"..."}`
/// 3. 收到 `auth_ok` 后订阅 `subscribe_events` (event_type=state_changed)
/// 4. 收到事件后解析 `new_state` 并回调
// Swift 6：收发均在专用队列与主线程间流转，@unchecked Sendable 声明可跨并发域持有
final class HAWebSocketController: NSObject, @unchecked Sendable {
    private let baseURL: URL
    private let token: String
    private let ignoreSSL: Bool
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var nextId: Int = 1
    private var onState: (@Sendable (HAEntity) -> Void)?
    // URLSession 的 delegateQueue 要求 OperationQueue，不能用 DispatchQueue
    private let queue = OperationQueue()

    private let decoder: JSONDecoder = {
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
                                                     debugDescription: s))
        }
        return d
    }()

    init(settings: ConnectionSettings) {
        self.baseURL = URL(string: settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(fileURLWithPath: "/")
        self.token = settings.token
        self.ignoreSSL = settings.ignoreSSL
        super.init()
        // 串行队列，保证回调按序处理
        queue.maxConcurrentOperationCount = 1
    }

    /// 建立连接并开始订阅实时事件。
    /// - Parameter onState: 每当某实体状态变化时，在主线程回调最新实体。
    func connect(onState: @escaping @Sendable (HAEntity) -> Void) {
        self.onState = onState
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return }
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        let path = comps.path == "/" ? "" : comps.path
        comps.path = path + "/api/websocket"
        guard let url = comps.url else { return }

        let config = URLSessionConfiguration.default
        let delegate = ignoreSSL ? HAURLSessionDelegate() : nil
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: queue)
        task = session?.webSocketTask(with: url)
        task?.resume()
        receiveAuth()
        receiveLoop()
    }

    private func receiveAuth() {
        task?.receive { [weak self] result in
            guard let self else { return }
            if case .success(let msg) = result,
               case .string(let text) = msg,
               let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String, type == "auth_required" {
                self.send(["type": "auth", "access_token": self.token])
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let text) = msg { self.handleMessage(text) }
                self.receiveLoop()
            case .failure(let err):
                print("[HA-WS] 接收循环结束: \(err.localizedDescription)")
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "auth_ok":
            // 订阅全部状态变化事件
            send(["id": nextId, "type": "subscribe_events", "event_type": "state_changed"])
            nextId += 1
            print("[HA-WS] 已认证并订阅 state_changed")

        case "event":
            guard let event = json["event"] as? [String: Any],
                  (event["event_type"] as? String) == "state_changed",
                  let dataObj = event["data"] as? [String: Any],
                  let newState = dataObj["new_state"] as? [String: Any],
                  let entityData = try? JSONSerialization.data(withJSONObject: newState),
                  let entity = try? decoder.decode(HAEntity.self, from: entityData) else { return }
            // 取局部副本，避免在 @Sendable 闭包中捕获 self 触发并发检查
            let callback = self.onState
            DispatchQueue.main.async { callback?(entity) }

        case "auth_invalid":
            print("[HA-WS] 认证失败：令牌无效")

        default:
            break
        }
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { err in
            if let err { print("[HA-WS] 发送失败: \(err.localizedDescription)") }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
