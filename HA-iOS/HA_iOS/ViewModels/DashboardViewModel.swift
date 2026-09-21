import Foundation
import SwiftUI

/// 仪表盘核心状态机：管理连接、实体列表、实时更新与收藏。
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var entities: [HAEntity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isConnected = false
    @Published var favoriteIds: Set<String> = []

    private var client: HAClient?
    private var ws: HAWebSocketController?
    private let favoritesKey = "com.ha.ios.favorites"

    /// 按 domain 分组的实体（用于分组列表）
    var grouped: [String: [HAEntity]] {
        Dictionary(grouping: entities) { $0.domain }
            .mapValues { $0.sorted { $0.friendlyName < $1.friendlyName } }
    }

    /// 已排序的 domain 列表（控制分组顺序）
    var domainOrder: [String] {
        grouped.keys.sorted()
    }

    /// 收藏的实体（按名字排序）
    var favorites: [HAEntity] {
        entities
            .filter { favoriteIds.contains($0.entityId) }
            .sorted { $0.friendlyName < $1.friendlyName }
    }

    init() {
        loadFavorites()
    }

    // MARK: - 连接

    func connect(settings: ConnectionSettings) {
        do {
            client = try HAClient(settings: settings)
        } catch {
            errorMessage = (error as? HAClientError)?.errorDescription ?? error.localizedDescription
            return
        }

        Task { await loadStates() }

        ws = HAWebSocketController(settings: settings)
        ws?.connect { [weak self] entity in
            Task { @MainActor in
                self?.applyRealtimeUpdate(entity)
            }
        }
    }

    func disconnect() {
        ws?.disconnect()
        ws = nil
        isConnected = false
    }

    func loadStates() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        do {
            let list = try await client.fetchStates()
            entities = list.sorted { $0.friendlyName < $1.friendlyName }
            isConnected = true
        } catch {
            errorMessage = (error as? HAClientError)?.errorDescription ?? error.localizedDescription
            isConnected = false
        }
        isLoading = false
    }

    // MARK: - 实时更新

    private func applyRealtimeUpdate(_ entity: HAEntity) {
        if let idx = entities.firstIndex(where: { $0.entityId == entity.entityId }) {
            entities[idx] = entity
        }
    }

    // MARK: - 控制

    func toggle(_ entity: HAEntity) {
        guard let client else { return }
        Task {
            do {
                try await client.toggle(entity)
                // 实际状态由 WebSocket 事件刷新
            } catch {
                // 本类整体为 @MainActor，Task 继承主 actor 隔离，可直接更新状态
                self.errorMessage = (error as? HAClientError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func callService(domain: String, service: String, entityId: String) {
        guard let client else { return }
        Task {
            do {
                try await client.callService(domain: domain, service: service, entityId: entityId)
            } catch {
                self.errorMessage = (error as? HAClientError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - 收藏

    func toggleFavorite(_ entity: HAEntity) {
        if favoriteIds.contains(entity.entityId) {
            favoriteIds.remove(entity.entityId)
        } else {
            favoriteIds.insert(entity.entityId)
        }
        saveFavorites()
    }

    func isFavorite(_ entity: HAEntity) -> Bool {
        favoriteIds.contains(entity.entityId)
    }

    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            favoriteIds = Set(arr)
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(Array(favoriteIds)) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
}
