import SwiftUI

struct AppNavigationView: View {
    @State private var selectedSection: SiteSection = {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--tab"), arguments.indices.contains(index + 1) {
            return SiteSection(rawValue: arguments[index + 1]) ?? .home
        }
        return .home
    }()
    @State private var photos = PhotoLibraryStore()
    @State private var dashboard = DashboardStore()
    @State private var repository = GitHubRepository()
    @Environment(\.scenePhase) private var scenePhase
    @State private var account = AccountStore()
    @State private var showingAccount = ProcessInfo.processInfo.arguments.contains("--account")

    var body: some View {
        Group {
            if #available(iOS 18, *) {
                modernTabs
            } else {
                legacyTabs
            }
        }
        .tint(.appAccent)
        .sheet(isPresented: $showingAccount) {
            AccountScreen(store: account)
        }
        .task {
            await account.restore()
        }
        .task(id: account.credentialRevision) {
            let token = account.currentToken()
            await repository.updateToken(token)
            dashboard.updateToken(token)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await account.refreshAuthorization() }
            }
        }
    }

    @available(iOS 18, *)
    private var modernTabs: some View {
        TabView(selection: $selectedSection) {
            ForEach(SiteSection.allCases) { section in
                Tab(section.title, systemImage: section.symbolName, value: section) {
                    sectionContent(section)
                }
            }
        }
    }

    private var legacyTabs: some View {
        TabView(selection: $selectedSection) {
            ForEach(SiteSection.allCases) { section in
                sectionContent(section)
                    .tabItem { Label(section.title, systemImage: section.symbolName) }
                    .tag(section)
            }
        }
    }

    private func sectionContent(_ section: SiteSection) -> some View {
        NavigationStack {
            Group {
                switch section {
                case .home:
                    HomeScreen(store: dashboard)
                case .photos:
                    PhotosScreen(store: photos, repository: repository, canPublish: account.isSignedIn)
                case .blog:
                    BlogScreen(repository: repository)
                case .talks:
                    TalksScreen(repository: repository, canPublish: account.isSignedIn)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { profileToolbar }
        }
    }

    @ToolbarContentBuilder
    private var profileToolbar: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarTrailing) { profileButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { profileButton }
        }
    }

    private var profileButton: some View {
        Button {
            showingAccount = true
        } label: {
            ProfileAvatar(isSignedIn: account.isSignedIn, avatarURL: account.avatarURL)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(account.isSignedIn ? "个人中心，\(account.name)" : "个人中心，未登录")
        .accessibilityHint("登录、外观和博客设置")
    }
}
