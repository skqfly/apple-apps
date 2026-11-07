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
    @State private var pending: PendingChangesStore
    @State private var library: ContentLibraryStore

    init() {
        let pending = PendingChangesStore()
        _pending = State(initialValue: pending)
        _library = State(initialValue: ContentLibraryStore(pending: pending))
    }
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
            library.syncPhotos(photos.photos)
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
                    HomeScreen(store: dashboard, pending: pending, repository: repository, canPush: account.isSignedIn)
                case .photos:
                    PhotosScreen(store: photos, repository: repository, pending: pending, library: library, canPublish: account.isSignedIn)
                case .blog:
                    BlogScreen(repository: repository)
                case .talks:
                    TalksScreen(repository: repository, pending: pending, photos: photos, library: library, canPublish: account.isSignedIn, authorName: account.name, avatarURL: account.avatarURL)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { profileToolbar }
        }
    }

    @ToolbarContentBuilder
    private var profileToolbar: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarLeading) { profileButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { profileButton }
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

/// Keeps the avatar's glass treatment and gives older systems a small press response.
private struct ProfileGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}
