import SwiftUI

/// 收藏视图：展示被标记为常用的实体，快速控制。
struct FavoritesView: View {
    @EnvironmentObject private var vm: DashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if vm.favorites.isEmpty {
                    // iOS 26：原生空态视图
                    ContentUnavailableView("还没有收藏", systemImage: "star",
                        description: Text("在设备页把常用设备加入收藏，会显示在这里。"))
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
}
