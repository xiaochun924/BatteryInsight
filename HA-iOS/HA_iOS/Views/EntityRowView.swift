import SwiftUI

/// 单个实体的列表行：图标 + 名称 + 状态摘要；可开关实体附带 Toggle。
struct EntityRowView: View {
    @EnvironmentObject private var vm: DashboardViewModel
    let entity: HAEntity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entity.iconName)
                .foregroundStyle(entity.isOn ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 34)
                .font(.title3)
                // iOS 26 液态玻璃底座
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.friendlyName).lineLimit(1)
                Text(stateSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if entity.isToggleable {
                Toggle("", isOn: Binding(
                    get: { entity.isOn },
                    set: { _ in vm.toggle(entity) }
                ))
                .labelsHidden()
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var stateSummary: String {
        if let unit = entity.unit {
            return "\(entity.state) \(unit)"
        }
        return entity.state
    }
}
