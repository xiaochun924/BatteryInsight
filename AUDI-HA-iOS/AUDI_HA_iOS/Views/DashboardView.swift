import SwiftUI

/// 设备仪表盘：按 domain 分组展示全部实体，支持下拉刷新与点击进入详情。
struct DashboardView: View {
    @EnvironmentObject private var vm: DashboardViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("AUDI-HA")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await vm.loadStates() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
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
            emptyState("没有实体", "连接成功，但此实例暂无可用实体。", "tray")
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

    /// iOS 16 兼容的空状态视图（ContentUnavailableView 需 iOS 17+）
    @ViewBuilder
    private func emptyState(_ title: String, _ message: String, _ icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
