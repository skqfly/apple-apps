import SwiftUI

@MainActor
struct AccountScreen: View {
    let store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GitHubLoginScreen(store: store)
                    } label: {
                        if store.isSignedIn {
                            AccountProfileView(name: store.name, avatarURL: store.avatarURL)
                        } else {
                            Label {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("登录 GitHub").font(.headline)
                                    Text("连接网站仓库，发布说说和照片")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "person.crop.circle").font(.title)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                Section("管理") {
                    NavigationLink {
                        WebsiteSettingsScreen()
                    } label: {
                        Label("网站与博客", systemImage: "globe")
                    }
                    NavigationLink {
                        PublishingSettingsScreen()
                    } label: {
                        Label("发布与同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Section("偏好") {
                    NavigationLink {
                        AppearanceSettingsScreen()
                    } label: {
                        Label("外观", systemImage: "circle.lefthalf.filled")
                    }
                    NavigationLink {
                        AppInformationScreen()
                    } label: {
                        Label("关于栖页", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("个人中心")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .tint(.appAccent)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .task { await store.restore() }
    }
}
