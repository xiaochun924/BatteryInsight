import SwiftUI

/// 建议页：基于采集数据生成的保养与省电提示
struct TipsView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    var body: some View {
        NavigationStack {
            List(vm.tips) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tip.icon)
                        .foregroundStyle(tip.tint)
                        .frame(width: 26)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tip.title)
                            .font(.subheadline.bold())
                        Text(tip.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.insetGrouped)
            // 液态玻璃悬浮顶栏：返回按钮 + 居中胶囊标题
            .liquidGlassTopBar(title: "优化建议")
        }
    }
}
