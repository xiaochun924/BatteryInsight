import SwiftUI

@main
struct BatteryInsightApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                // P0-1：退后台时把 pending 的采样/记录变更立即落盘
                // （平时 save 已降频挪后台，退后台这一刻必须保证数据完整）
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        DataStore.shared.flushNow()
                    }
                }
        }
    }
}
