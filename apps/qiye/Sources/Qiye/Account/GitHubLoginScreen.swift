import SwiftUI

struct GitHubLoginScreen: View {
    let store: AccountStore
    @Environment(\.openURL) private var openURL
    @State private var confirmsLogout = false

    var body: some View {
        Form {
            if store.isSignedIn {
                Section { AccountProfileView(name: store.name, avatarURL: store.avatarURL) }
                Section {
                    Button("退出登录", role: .destructive) { confirmsLogout = true }
                        .confirmationDialog("退出 GitHub 登录？", isPresented: $confirmsLogout, titleVisibility: .visible) {
                            Button("退出登录", role: .destructive) { store.logout() }
                        } message: {
                            Text("此手机保存的授权凭据将被删除。")
                        }
                }
            } else if let code = store.deviceCode {
                Section("在 GitHub 完成授权") {
                    Text("复制这组代码，然后在 GitHub 页面输入。")
                    Text(code.userCode)
                        .font(.largeTitle.monospaced().bold())
                        .textSelection(.enabled)
                        .accessibilityLabel("授权码 \(code.userCode)")
                    Button("打开 GitHub 授权页面", systemImage: "arrow.up.right.square") {
                        openURL(code.verificationURI)
                    }
                    ProgressView("等待你在 GitHub 上确认…")
                    Button("取消", role: .cancel) { store.cancelGitHubLogin() }
                }
            } else {
                Section {
                    Label("通过 GitHub 登录", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Text("登录后可以把说说和照片发布到你的公开网站仓库。")
                        .foregroundStyle(.secondary)
                    Button("使用 GitHub 登录", systemImage: "arrow.up.right.square") {
                        store.beginGitHubLogin()
                    }
                    .disabled(store.isLoading || store.clientID.isEmpty)
                    if store.isLoading { ProgressView("正在连接 GitHub…") }
                }
                if store.clientID.isEmpty {
                    Section("配置待完成") {
                        Text("需要先为栖页注册 GitHub OAuth App，并启用 Device Flow。")
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
                Text("授权在 GitHub 官方页面完成，密码不会交给栖页。授权凭据仅保存在这台设备的钥匙串中。")
                Text("公开仓库权限用于提交说说、照片及读取工作流；GitHub OAuth 的 public_repo 权限适用于账号下的公开仓库。")
            } header: {
                Text("授权说明")
            }
        }
        .navigationTitle("GitHub 账户")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--device-login") {
                store.beginGitHubLogin()
            }
        }
        #endif
    }
}
