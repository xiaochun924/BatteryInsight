import SwiftUI

/// 设置页：配置「分析」按钮调用的快捷指令。
///
/// 用户已在「快捷指令」App 中建好指令（选择文件 → 打开本 App）。
/// 在首页右上角点击设置齿轮进入本页，填好指令名称后，
/// 首页「分析」按钮会直接运行该快捷指令；留空则回退为系统文件选择器。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("battery.shortcutName") private var shortcutName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("快捷指令名称", text: $shortcutName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("快捷指令")
                } footer: {
                    Text("在「快捷指令」App 中创建一条指令：选择文件 → 打开本 App。设置名称后，点击首页右上角「分析」会直接运行该快捷指令；留空则回退为系统文件选择器。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            // 液态玻璃悬浮顶栏（与全 App 统一）：左上角关闭 + 右上角绿色对勾确认，
            // 与寿命预测页同款左右对称布局
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 8) {
                // sheet 顶部有大圆角：加大水平边距对齐圆角，与圆角留出呼吸间距
                GlassTopBar(title: "设置", horizontalPadding: 28,
                            leading: { GlassCircleButton(icon: "xmark") { dismiss() } },
                            trailing: { GlassCircleButton(icon: "checkmark", tint: .green) { dismiss() } })
            }
        }
        .presentationDetents([.medium])
    }
}
