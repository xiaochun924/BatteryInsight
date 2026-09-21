import SwiftUI

/// 首次配置连接：输入实例地址、长期访问令牌，并先验证连通性再保存。
struct ConnectionView: View {
    @State private var baseURL = ""
    @State private var token = ""
    @State private var ignoreSSL = false
    @State private var error: String?
    @State private var testing = false
    let onConnected: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Home Assistant 实例地址") {
                    TextField("https://home.example.com:8123", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Toggle("忽略 SSL 证书错误（自签 https）", isOn: $ignoreSSL)
                }
                Section("长期访问令牌") {
                    SecureField("粘贴 Long-Lived Access Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button(action: verifyAndSave) {
                        HStack {
                            if testing { ProgressView() }
                            Text(testing ? "验证连接中…" : "保存并连接")
                        }
                    }
                    // iOS 26 液态玻璃主按钮
                    .buttonStyle(.glassProminent)
                    .disabled(baseURL.isEmpty || token.isEmpty || testing)
                }
                Section("如何获取令牌") {
                    Text("登录 HA 网页端 → 左下角用户头像 → 长期访问令牌 → 创建令牌，复制生成的字符串粘贴到上方。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("连接设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func verifyAndSave() {
        let settings = ConnectionSettings(baseURL: baseURL, token: token, ignoreSSL: ignoreSSL)
        testing = true
        error = nil
        Task {
            do {
                let client = try HAClient(settings: settings)
                _ = try await client.fetchStates()
                SettingsStore.shared.save(settings)
                await MainActor.run {
                    testing = false
                    onConnected()
                }
            } catch {
                await MainActor.run {
                    testing = false
                    self.error = (error as? HAClientError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}
