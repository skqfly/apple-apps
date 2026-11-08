import SwiftUI

struct GitHubLoginScreen: View {
    let store: AccountStore
    @State private var token = ""
    @State private var confirmsLogout = false
    @State private var loginTask: Task<Void, Never>?
    @FocusState private var tokenFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            if store.isSignedIn {
                Section {
                    AccountProfileView(name: store.name, avatarURL: store.avatarURL)
                }

                Section {
                    Button(role: .destructive) {
                        Haptics.light()
                        confirmsLogout = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("退出登录")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                    .confirmationDialog("退出 GitHub 登录？", isPresented: $confirmsLogout, titleVisibility: .visible) {
                        Button("退出登录", role: .destructive) {
                            Haptics.medium()
                            store.logout()
                        }
                    } message: {
                        Text("会删除这台设备钥匙串里的登录凭据。")
                    }
                }
            } else {
                Section {
                    SecureField("GitHub Personal Access Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .privacySensitive()
                        .focused($tokenFocused)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                        .disabled(store.isLoading)
                        .accessibilityIdentifier("github-token-field")

                    Button {
                        signIn()
                    } label: {
                        HStack {
                            Spacer()
                            if store.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 6)
                                Text("正在验证…")
                                    .font(.subheadline.weight(.semibold))
                            } else {
                                Label("验证并登录", systemImage: "arrow.right.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .liquidGlassProminent(tint: Color.appAccent, cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isLoading || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("使用 Token 登录")
                } footer: {
                    Text("仅登录 skqfly 账号；验证成功后保存在设备钥匙串中，不会上传或同步到云端。")
                }

                Section("创建 Token 指引") {
                    Link("前往 GitHub 创建 Fine-grained Token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                        .font(.subheadline.weight(.medium))

                    Text("Resource owner 选择 skqfly，仅勾选 skqfly.github.io 仓库。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("权限设置：Contents 选 Read and write，Actions 选 Read-only。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    DisclosureGroup("也可以使用 Classic Token") {
                        Link("创建 Classic Token", destination: URL(string: "https://github.com/settings/tokens/new?scopes=public_repo&description=Qiye")!)
                            .font(.subheadline)
                        Text("只需勾选 public_repo 权限范围。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = store.error {
                Section("提示") {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("GitHub 账户")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            token = ""
            loginTask?.cancel()
        }
    }

    private func signIn() {
        guard !store.isLoading else { return }
        tokenFocused = false
        Haptics.medium()
        loginTask = Task {
            if await store.signIn(token: token) {
                token = ""
                Haptics.success()
            } else {
                Haptics.error()
            }
        }
    }
}
