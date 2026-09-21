import SwiftUI

extension Notification.Name {
    /// 在设置页点击「断开并清除配置」后发出，用于切回连接页
    static let haDidDisconnect = Notification.Name("com.audi.ha.didDisconnect")
}

/// 应用根视图：根据是否已配置连接，决定展示连接页还是主仪表盘。
struct RootView: View {
    @EnvironmentObject private var vm: DashboardViewModel
    @State private var configured: Bool = SettingsStore.shared.isConfigured

    var body: some View {
        Group {
            if configured {
                DashboardTabView()
            } else {
                ConnectionView {
                    configured = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .haDidDisconnect)) { _ in
            configured = false
        }
    }
}

/// 主 Tab：设备 / 收藏 / 设置
struct DashboardTabView: View {
    @EnvironmentObject private var vm: DashboardViewModel

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("设备", systemImage: "house.fill") }

            FavoritesView()
                .tabItem { Label("收藏", systemImage: "star.fill") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .onAppear {
            if let settings = SettingsStore.shared.settings {
                vm.connect(settings: settings)
            }
        }
    }
}
