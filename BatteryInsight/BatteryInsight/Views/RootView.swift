import SwiftUI

/// 应用根视图。
///
/// 原先这里是「概览 / 趋势 / 充电 / 健康」四个 Tab。现在只剩一页
/// 「电池健康」，TabView 没有意义了，直接用 NavigationStack：
/// 单 Tab 会在底部留一条只有一个胶囊的空 Tab Bar，反而占地方。
struct RootView: View {
    @StateObject private var vm = BatteryViewModel()
    @Environment(\.scenePhase) private var scenePhase
    /// 从「文件」App / 分享菜单用本 App 打开日志后的解析结果
    @State private var showingOpenResult = false

    var body: some View {
        NavigationStack {
            BatteryHomeView()
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
