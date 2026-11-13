import SwiftUI

@MainActor
struct AccountScreen: View {
    let store: AccountStore
    let library: ContentLibraryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "dark"
    #if DEBUG
    @State private var showsLogin = ProcessInfo.processInfo.arguments.contains("--login")
    #endif

    private var deletedCount: Int {
        library.photos(in: .deleted).count + library.talks(in: .deleted).count
    }

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
                        TrashScreen(library: library)
                    } label: {
                        HStack {
                            Label("回收站", systemImage: "trash")
                            Spacer()
                            if deletedCount > 0 {
                                Text("\(deletedCount)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.red)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.12), in: Capsule())
                            }
                        }
                    }

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

                    NavigationLink {
                        BackupScreen()
                    } label: {
                        Label("备份与恢复", systemImage: "externaldrive.badge.icloud")
                    }
                }

                Section("偏好") {
                    NavigationLink {
                        AppearanceSettingsScreen()
                    } label: {
                        Label("外观与主题色", systemImage: "paintpalette")
                    }

                    NavigationLink {
                        AppInformationScreen()
                    } label: {
                        Label("关于栖页", systemImage: "info.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("个人中心")
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            .navigationDestination(isPresented: $showsLogin) {
                GitHubLoginScreen(store: store)
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .tint(.primary)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .task { await store.restore() }
    }
}
