import SwiftUI

struct AppNavigationView: View {
    @State private var selectedSection: SiteSection = {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--tab"), arguments.indices.contains(index + 1) {
            return SiteSection(rawValue: arguments[index + 1]) ?? .home
        }
        return .home
    }()
    @State private var photos: PhotoLibraryStore
    @State private var dashboard = DashboardStore()
    @State private var repository: GitHubRepository
    @State private var pending: PendingChangesStore
    @State private var library: ContentLibraryStore
    @State private var blog: BlogStore
    @State private var talks: TalksStore
    @State private var directory: SiteDirectoryStore
    @State private var offlineWebsite: OfflineWebsite?
    @State private var offlineError: String?
    @State private var isSyncingOffline = false
    @State private var offlineSync = OfflineWebsiteSync()
    @State private var showingStudio = false

    init() {
        let pending = PendingChangesStore()
        let repository = GitHubRepository()
        let photos = PhotoLibraryStore()
        let blog = BlogStore(repository: repository)
        let talks = TalksStore(repository: repository)
        let directory = SiteDirectoryStore(repository: repository)
        let offlineWebsite = OfflineWebsite.current()
        if let offlineWebsite {
            photos.useOfflineSnapshot(offlineWebsite, authoritative: false)
            blog.useOfflineSnapshot(offlineWebsite)
            talks.useOfflineSnapshot(offlineWebsite, authoritative: false)
            directory.useOfflineSnapshot(offlineWebsite)
        }
        _repository = State(initialValue: repository)
        _photos = State(initialValue: photos)
        _blog = State(initialValue: blog)
        _talks = State(initialValue: talks)
        _directory = State(initialValue: directory)
        _offlineWebsite = State(initialValue: offlineWebsite)
        _pending = State(initialValue: pending)
        _library = State(initialValue: ContentLibraryStore(pending: pending))
    }
    @Environment(\.scenePhase) private var scenePhase
    @State private var account = AccountStore()
    @State private var showingAccount = ProcessInfo.processInfo.arguments.contains("--account")

    var body: some View {
        Group {
            if #available(iOS 18, *) { modernTabs }
            else { legacyTabs }
        }
        .appPageBackground()
        .tint(.primary)
        .sheet(isPresented: $showingAccount) {
            AccountScreen(store: account, library: library, offlineError: offlineError,
                          isSyncingOffline: isSyncingOffline, refreshOffline: refreshOfflineWebsite)
        }
        .sheet(isPresented: $showingStudio) {
            NavigationStack {
                HomeScreen(store: dashboard, pending: pending, repository: repository, canPush: account.isSignedIn)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showingStudio = false
                            } label: {
                                ToolbarActionIcon("关闭", systemImage: "xmark")
                            }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
        .task {
            library.syncPhotos(photos.photos, authoritative: photos.hasRemoteSnapshot)
            library.syncTalks(talks.posts, authoritative: false)
            await account.restore()
        }
        .task(id: account.credentialRevision) {
            let token = account.currentToken()
            await repository.updateToken(token)
            dashboard.updateToken(token)
            if token != nil { await refreshOfflineWebsite() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await account.refreshAuthorization()
                    await refreshOfflineWebsite()
                }
            }
        }
        .environment(\.offlineWebsite, offlineWebsite)
    }

    private func refreshOfflineWebsite() async {
        guard account.currentToken() != nil, !isSyncingOffline else { return }
        isSyncingOffline = true
        offlineError = nil
        defer { isSyncingOffline = false }
        do {
            guard let snapshot = try await offlineSync.sync(repository: repository),
                  snapshot.directory != offlineWebsite?.directory else { return }
            offlineWebsite = snapshot
            photos.useOfflineSnapshot(snapshot, authoritative: true)
            blog.useOfflineSnapshot(snapshot)
            talks.useOfflineSnapshot(snapshot, authoritative: true)
            directory.useOfflineSnapshot(snapshot)
            library.syncPhotos(photos.photos, authoritative: photos.hasRemoteSnapshot)
            library.syncTalks(talks.posts, authoritative: talks.hasRemoteSnapshot)
        } catch is CancellationError { }
        catch let error as URLError where error.code == .cancelled { }
        catch {
            offlineError = "无法更新离线副本。\(error.localizedDescription)"
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
                    CollectionsScreen(blog: blog, photos: photos, library: library,
                                      directory: directory, canEditDirectory: account.isSignedIn, open: { section in
                                          selectedSection = section
                                      }, showAccount: { showingAccount = true }, showStudio: { showingStudio = true })
                case .photos:
                    PhotosScreen(store: photos, repository: repository, pending: pending, library: library, canPublish: account.isSignedIn)
                case .blog:
                    BlogScreen(store: blog)
                case .talks:
                    TalksScreen(store: talks, pending: pending, photos: photos, library: library, canPublish: account.isSignedIn, authorName: account.name, avatarURL: account.avatarURL)
                }
            }
        }
    }

}

extension EnvironmentValues {
    @Entry var offlineWebsite: OfflineWebsite? = nil
}
