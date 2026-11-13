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
    @State private var blog: BlogStore
    @State private var showingStudio = false
    @Namespace private var tabHighlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        let pending = PendingChangesStore()
        let repository = GitHubRepository()
        _repository = State(initialValue: repository)
        _blog = State(initialValue: BlogStore(repository: repository))
        _pending = State(initialValue: pending)
        _library = State(initialValue: ContentLibraryStore(pending: pending))
    }
    @Environment(\.scenePhase) private var scenePhase
    @State private var account = AccountStore()
    @State private var showingAccount = ProcessInfo.processInfo.arguments.contains("--account")

    var body: some View {
        TabView(selection: $selectedSection) {
            ForEach(SiteSection.allCases) { section in
                sectionContent(section).tag(section)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { floatingNavigation }
        .background(Color.appBackground)
        .tint(.primary)
        .sheet(isPresented: $showingAccount) {
            AccountScreen(store: account, library: library)
        }
        .sheet(isPresented: $showingStudio) {
            NavigationStack {
                HomeScreen(store: dashboard, pending: pending, repository: repository, canPush: account.isSignedIn)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showingStudio = false }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
        .task {
            library.syncPhotos(photos.photos, authoritative: photos.hasRemoteSnapshot)
            library.syncTalks(TalksStore(repository: repository).posts, authoritative: false)
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

    private var floatingNavigation: some View {
        HStack(spacing: 4) {
            ForEach(SiteSection.allCases) { section in
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : CollectionStyle.spring) { selectedSection = section }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: section == selectedSection ? section.selectedSymbol : section.symbolName)
                            .font(.system(size: 19, weight: .medium))
                        Text(section.title).font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .foregroundStyle(section == selectedSection ? Color.primary : Color.secondary)
                    .background {
                        if section == selectedSection {
                            Capsule().fill(Color.primary.opacity(0.10))
                                .matchedGeometryEffect(id: "tab", in: tabHighlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(CollectionPressStyle())
                .accessibilityIdentifier("tab-\(section.rawValue)")
                .accessibilityAddTraits(section == selectedSection ? [.isSelected] : [])
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.24), radius: 20, y: 8)
        .frame(maxWidth: 400)
        .padding(.horizontal, 28).padding(.bottom, 8).padding(.top, 8)
    }

    private func sectionContent(_ section: SiteSection) -> some View {
        NavigationStack {
            Group {
                switch section {
                case .home:
                    CollectionsScreen(blog: blog, photos: photos, library: library, repository: repository,
                                      open: { section in
                                          withAnimation(reduceMotion ? nil : CollectionStyle.spring) { selectedSection = section }
                                      }, showAccount: { showingAccount = true }, showStudio: { showingStudio = true })
                case .photos:
                    PhotosScreen(store: photos, repository: repository, pending: pending, library: library, canPublish: account.isSignedIn)
                case .blog:
                    BlogScreen(store: blog)
                case .talks:
                    TalksScreen(repository: repository, pending: pending, photos: photos, library: library, canPublish: account.isSignedIn, authorName: account.name, avatarURL: account.avatarURL)
                }
            }
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
        }
    }

}
