import SwiftUI

@main
struct BatteryInsightApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            // P0-1：采样已降频（addSample 只标记脏数据不落盘），
            // 退后台 / 进入后台时把积压的采样一次性全量保存，
            // 否则最近 15 秒的采样会在 App 被杀时丢失
            if phase != .active {
                Task { @MainActor in DataStore.shared.flushIfNeeded() }
            }
        }
    }
}
