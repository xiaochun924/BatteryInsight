import SwiftUI

/// 应用主 Tab
///
/// ⚠️ 这里**只放 4 个** Tab，是有原因的：
/// iOS 26 的 Liquid Glass Tab Bar 是悬浮胶囊样式，窄屏下最多平铺 5 个；
/// 一旦超出，多出来的会被系统自动收纳进「More」页
/// （表现为底部多出一个「More」按钮、内容被胶囊遮挡，看起来不像全屏）。
/// 因此「日志」改从「健康」页右上角进入。
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
        }
        .environmentObject(vm)
        .onChange(of: scenePhase) { phase in
            // 后台期间定时器被系统挂起，回到前台立即补一次刷新
            if phase == .active { vm.refresh() }
        }
    }
}
