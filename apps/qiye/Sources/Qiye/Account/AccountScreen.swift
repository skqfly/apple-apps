import SwiftUI

/// Present as `.sheet { AccountScreen(store: accountStore) }`.
@MainActor
struct AccountScreen: View {
    let store: AccountStore

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @State private var token = ""
    @State private var showsLogoutConfirmation = false
    @State private var showsClearConfirmation = false
    @State private var loginTask: Task<Void, Never>?
    @FocusState private var tokenIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if store.isSignedIn {
                    profileSection
                } else {
                    loginSection
                }

                if store.isLoading {
                    Section {
                        ProgressView("正在向 GitHub 验证身份…")
                            .accessibilityLabel("正在向 GitHub 验证身份，请稍候")
                    }
                }

                if let error = store.error {
                    Section("验证状态") {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("验证提示：\(error)")

                        if !store.isSignedIn {
                            Button("重新验证已保存的登录凭证") {
                                loginTask = Task { await store.restore() }
                            }
                            .disabled(store.isLoading)
                        }
                    }
                }

                AccountSettingsSection()

                Section {
                    Text("当前登录仅验证 GitHub 身份，尚未授予 Trilium 内容读取或发布权限。")
                    Text("私人令牌仅保存在此设备的钥匙串中，不会同步到 iCloud。退出登录会删除本机令牌；如需撤销令牌，请前往 GitHub 设置。")
                } header: {
                    Text("栖页 · 账户与隐私")
                }

                if !store.isSignedIn {
                    Section {
                        Button("清除本机登录凭证", role: .destructive) {
                            showsClearConfirmation = true
                        }
                        .confirmationDialog("清除本机登录凭证？", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
                            Button("清除凭证", role: .destructive) {
                                clearCredentials()
                            }
                            Button("取消", role: .cancel) { }
                        } message: {
                            Text("会删除钥匙串中保存的 GitHub 令牌。")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("账户与设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityHint("关闭账户与设置")
                }
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .task { await store.restore() }
        .onChange(of: store.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                token = ""
                tokenIsFocused = false
            }
        }
        .onDisappear {
            token = ""
            loginTask?.cancel()
            loginTask = nil
        }
    }

    private var loginSection: some View {
        Section {
            Text("登录栖页")
                .font(.headline)
            Text("使用 skqfly 的 GitHub Personal Access Token 验证个人身份。")
                .foregroundStyle(.secondary)

            SecureField("GitHub Personal Access Token", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .privacySensitive()
                .focused($tokenIsFocused)
                .submitLabel(.go)
                .onSubmit(signIn)
                .disabled(store.isLoading)
                .accessibilityLabel("GitHub 私人访问令牌")
                .accessibilityHint("安全输入，仅支持 skqfly 账户的令牌")

            Button("验证并登录", systemImage: "person.crop.circle.badge.checkmark", action: signIn)
                .disabled(store.isLoading || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let url = URL(string: "https://github.com/settings/personal-access-tokens/new") {
                Link(destination: url) {
                    Label("创建 GitHub 令牌 · 在浏览器打开", systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text("个人登录")
        } footer: {
            Text("建议使用 Fine-grained token，设置到期时间，保留默认权限即可。当前仅通过 GET /user 读取账户基本身份，不需要仓库、内容写入、组织或邮箱权限；无需勾选额外权限。若使用 classic token，也无需勾选 scope。")
        }
    }

    private var profileSection: some View {
        Section {
            AccountProfileView(name: store.name, avatarURL: store.avatarURL)

            if let url = URL(string: "https://github.com/skqfly") {
                Link(destination: url) {
                    Label("GitHub 个人主页 · 在浏览器打开", systemImage: "arrow.up.right.square")
                }
            }

            Button("退出登录", role: .destructive) {
                showsLogoutConfirmation = true
            }
            .confirmationDialog("退出栖页？", isPresented: $showsLogoutConfirmation, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { clearCredentials() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("此设备钥匙串中保存的 GitHub 令牌将被删除。")
            }
        } header: {
            Text("个人资料")
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private func signIn() {
        guard !store.isLoading, !store.isSignedIn else { return }
        tokenIsFocused = false
        loginTask = Task {
            if await store.signIn(token: token) { token = "" }
        }
    }

    private func clearCredentials() {
        loginTask?.cancel()
        loginTask = nil
        token = ""
        store.logout()
    }
}
