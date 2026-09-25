import SwiftUI

/// 应用根视图。
///
/// 两个 Tab 页面，功能分开显示：
///   - 「电池健康」：设备信息 / 健康趋势 / 检测记录（BatteryHomeView）
///   - 「充电功率」：实时充电检测 / 充电统计 / 充电会话（ChargingPowerView）
///
/// 之前「概览 / 趋势 / 充电 / 健康」四个 Tab 被砍成只剩单页，
/// 现在按需求恢复为「电池健康 + 充电功率」两个独立页面。
struct RootView: View {
    @StateObject private var vm = BatteryViewModel()
    @Environment(\.scenePhase) private var scenePhase
    /// 从「文件」App / 分享菜单用本 App 打开日志后的解析结果
    @State private var showingOpenResult = false
    /// 当前选中的 Tab
    @State private var selectedTab: HomeTab = .health

    enum HomeTab: String, CaseIterable, Identifiable {
        case health = "电池健康"
        case power  = "充电功率"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .health: return "heart.fill"
            case .power:  return "bolt.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                BatteryHomeView()
            }
            .tabItem { Label(HomeTab.health.rawValue, systemImage: HomeTab.health.icon) }
            .tag(HomeTab.health)

            NavigationStack {
                ChargingPowerView()
            }
            .tabItem { Label(HomeTab.power.rawValue, systemImage: HomeTab.power.icon) }
            .tag(HomeTab.power)
        }
        .environmentObject(vm)
        .onChange(of: scenePhase) { phase in
            // 后台期间定时器被系统挂起，回到前台立即补一次刷新
            if phase == .active { vm.refresh() }
        }
        // 系统把文件「用本 App 打开」时回调（需在 Info.plist 里声明文档类型才会出现）
        .onOpenURL { url in
            Task {
                _ = await vm.importAnalyticsFiles([url])
                showingOpenResult = true
            }
        }
        .alert("导入结果", isPresented: $showingOpenResult) {
            Button("好", role: .cancel) { }
        } message: {
            Text(vm.importMessage ?? "")
        }
    }
}
