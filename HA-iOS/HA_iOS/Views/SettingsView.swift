import SwiftUI

/// 设置页：展示连接信息、重连/刷新、断开并清除配置。
struct SettingsView: View {
    @EnvironmentObject private var vm: DashboardViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("当前连接") {
                    if let s = SettingsStore.shared.settings {
                        LabeledContent("实例地址", value: s.baseURL)
                    }
                    HStack {
                        Text("状态")
                        Spacer()
                        Label(vm.isConnected ? "已连接" : "未连接",
                              systemImage: vm.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(vm.isConnected ? .green : .red)
                    }
                }
                Section {
                    Button { Task { await vm.loadStates() } } label: {
                        Label("刷新设备", systemImage: "arrow.clockwise")
                    }
                    Button {
                        vm.disconnect()
                        if let s = SettingsStore.shared.settings { vm.connect(settings: s) }
                    } label: {
                        Label("重新连接", systemImage: "wifi")
                    }
                }
                Section {
                    Button(role: .destructive) {
                        SettingsStore.shared.clear()
                        vm.disconnect()
                        NotificationCenter.default.post(name: .haDidDisconnect, object: nil)
                    } label: {
                        Label("断开并清除配置", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                Section("关于") {
                    LabeledContent("HA-iOS", value: "v1.0 · Home Assistant 衍生客户端")
                }
            }
            .navigationTitle("设置")
        }
    }
}
