import SwiftUI

/// 应用主 Tab
struct RootTabView: View {
    @StateObject private var vm = BatteryViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("概览", systemImage: "battery.100") }

            TrendsView()
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }

            ChargingView()
                .tabItem { Label("充电", systemImage: "bolt.fill") }

            HealthView()
                .tabItem { Label("健康", systemImage: "heart.fill") }

            AnalyticsView()
                .tabItem { Label("日志", systemImage: "doc.text.magnifyingglass") }

            TipsView()
                .tabItem { Label("建议", systemImage: "lightbulb.fill") }
        }
        .environmentObject(vm)
        .onChange(of: scenePhase) { phase in
            // 后台期间定时器被系统挂起，回到前台立即补一次刷新
            if phase == .active { vm.refresh() }
        }
    }
}
