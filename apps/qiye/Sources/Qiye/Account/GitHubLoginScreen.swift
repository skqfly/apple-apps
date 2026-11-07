import SwiftUI

struct GitHubLoginScreen: View {
    let store: AccountStore
    @State private var token = ""
    @State private var confirmsLogout = false
    @State private var loginTask: Task<Void, Never>?
    @FocusState private var tokenFocused: Bool

    var body: some View {
        Form {
            if store.isSignedIn {
                Section { AccountProfileView(name: store.name, avatarURL: store.avatarURL) }
                Section {
                    Button("退出登录", role: .destructive) { confirmsLogout = true }
                        .confirmationDialog("退出 GitHub 登录？", isPresented: $confirmsLogout, titleVisibility: .visible) {
                            Button("退出登录", role: .destructive) { store.logout() }
                        } message: { Text("会删除这台设备钥匙串里的登录凭据。") }
                }
            } else {
                Section {
                    SecureField("GitHub token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .privacySensitive()
                        .focused($tokenFocused)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                        .disabled(store.isLoading)
                        .accessibilityIdentifier("github-token-field")
                    Button("验证并登录", systemImage: "person.crop.circle.badge.checkmark", action: signIn)
                        .disabled(store.isLoading || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if store.isLoading { ProgressView("正在验证账户与网站仓库…") }
                } header: { Text("使用 token 登录") } footer: {
                    Text("仅登录 skqfly；验证成功后保存在设备钥匙串，不会写入网站或同步到 iCloud。")
                }
                Section("创建 token") {
                    Link("创建 Fine-grained token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                    Text("Resource owner 选择 skqfly，只选择 skqfly.github.io 仓库。")
                    Text("仓库权限：Contents 选 Read and write，Actions 选 Read-only；Metadata 保持默认。设置合适的到期日期。")
                        .foregroundStyle(.secondary)
                    DisclosureGroup("也可以使用 classic token") {
                        Link("创建 classic token", destination: URL(string: "https://github.com/settings/tokens/new?scopes=public_repo&description=Qiye")!)
                        Text("只需 public_repo；它可访问账号下所有公开仓库，Fine-grained token 的范围更小。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let error = store.error {
                Section("登录状态") {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Text("token 省去了浏览器授权步骤，仍需要手机网络能访问 api.github.com。请在此设备输入，不要发到聊天。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("GitHub 账户")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { token = ""; loginTask?.cancel() }
    }

    private func signIn() {
        guard !store.isLoading else { return }
        tokenFocused = false
        loginTask = Task {
            if await store.signIn(token: token) { token = "" }
        }
    }
}
