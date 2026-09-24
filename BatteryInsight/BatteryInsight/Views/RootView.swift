import SwiftUI

/// 应用根视图。
///
/// 原先这里是「概览 / 趋势 / 充电 / 健康」四个 Tab。现在只剩一页
/// 「电池健康」（含电量趋势），TabView 没有意义了，直接用 NavigationStack：
/// 单 Tab 会在底部留一条只有一个胶囊的空 Tab Bar，反而占地方。
struct RootView: View {
    @StateObject private var vm = BatteryViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            BatteryHomeView()
        }
        .environmentObject(vm)
        .onChange(of: scenePhase) { phase in
            // 后台期间定时器被系统挂起，回到前台立即补一次刷新
            if phase == .active { vm.refresh() }
        }
    }
}
