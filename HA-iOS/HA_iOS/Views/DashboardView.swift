import SwiftUI

/// 设备仪表盘：按 domain 分组展示全部实体，支持下拉刷新与点击进入详情。
struct DashboardView: View {
    @EnvironmentObject private var vm: DashboardViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("HA-iOS")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await vm.loadStates() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        // iOS 26 液态玻璃按钮
                        .buttonStyle(.glass)
                        .disabled(vm.isLoading)
                    }
                }
        }
        .alert("出错了", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("好") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.entities.isEmpty {
            ProgressView("加载设备…")
        } else if vm.entities.isEmpty {
            // iOS 26：直接使用原生空态视图（此前为兼容 iOS 16 才自绘）
            ContentUnavailableView("没有实体", systemImage: "tray",
                description: Text("连接成功，但此实例暂无可用实体。"))
        } else {
            List {
                ForEach(vm.domainOrder, id: \.self) { domain in
                    Section(domain.capitalized) {
                        ForEach(vm.grouped[domain] ?? []) { entity in
                            row(for: entity)
                        }
                    }
                }
            }
            .refreshable { await vm.loadStates() }
        }
    }

    /// 可开关的实体直接显示 Toggle（不进详情），其余点击进详情。
    @ViewBuilder
    private func row(for entity: HAEntity) -> some View {
        if entity.isToggleable {
            EntityRowView(entity: entity)
        } else {
            NavigationLink { EntityDetailView(entity: entity) } label: {
                EntityRowView(entity: entity)
            }
        }
    }
}
