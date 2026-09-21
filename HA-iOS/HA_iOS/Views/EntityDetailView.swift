import SwiftUI

/// 实体详情页：展示状态、控制按钮与全部 attributes。
struct EntityDetailView: View {
    @EnvironmentObject private var vm: DashboardViewModel
    let entity: HAEntity

    private var sortedAttributes: [(String, String)] {
        entity.attributes
            .sorted { $0.key < $1.key }
            .map { ($0.key, formatValue($0.value)) }
    }

    var body: some View {
        List {
            Section("状态") {
                LabeledContent("实体", entity.entityId)
                LabeledContent("当前状态", stateText)
                if let u = entity.unit { LabeledContent("单位", u) }
                if let t = entity.lastUpdated {
                    LabeledContent("更新时间", t.formatted())
                }
            }
            Section("控制") {
                if entity.isToggleable {
                    Button {
                        vm.toggle(entity)
                    } label: {
                        Label(entity.isOn ? "关闭" : "打开",
                              systemImage: entity.isOn ? "power" : "power.fill")
                    }
                    // iOS 26 液态玻璃按钮
                    .buttonStyle(.glass)
                } else {
                    Text("此实体不支持开关控制")
                        .foregroundStyle(.secondary)
                }
            }
            Section("属性 (attributes)") {
                if sortedAttributes.isEmpty {
                    Text("无").foregroundStyle(.secondary)
                } else {
                    ForEach(sortedAttributes, id: \.0) { key, value in
                        LabeledContent(key, value)
                    }
                }
            }
        }
        .navigationTitle(entity.friendlyName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stateText: String {
        if let u = entity.unit { return "\(entity.state) \(u)" }
        return entity.state
    }

    private func formatValue(_ v: HAAttributeValue) -> String {
        switch v {
        case .string(let s): return s
        case .number(let n): return String(format: "%.4g", n)
        case .bool(let b):    return b ? "true" : "false"
        case .array(let a):   return "[\(a.count) 项]"
        case .object:         return "{…}"
        case .null:           return "null"
        }
    }
}
