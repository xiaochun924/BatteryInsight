import SwiftUI

/// 收藏视图：展示被标记为常用的实体，快速控制。
struct FavoritesView: View {
    @EnvironmentObject private var vm: DashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if vm.favorites.isEmpty {
                    emptyState("还没有收藏", "在设备页把常用设备加入收藏，会显示在这里。", "star")
                } else {
                    List {
                        ForEach(vm.favorites) { entity in
                            if entity.isToggleable {
                                EntityRowView(entity: entity)
                            } else {
                                NavigationLink { EntityDetailView(entity: entity) } label: {
                                    EntityRowView(entity: entity)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("收藏")
        }
    }

    /// iOS 16 兼容的空状态视图（ContentUnavailableView 需 iOS 17+）
    @ViewBuilder
    private func emptyState(_ title: String, _ message: String, _ icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
