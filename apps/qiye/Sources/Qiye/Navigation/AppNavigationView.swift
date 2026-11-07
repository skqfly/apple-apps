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
    @State private var overview = SiteOverview()
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
        .task { await overview.refresh() }
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
                    HomeScreen(
                        overview: overview,
                        photoCount: photos.photos.count,
                        draftCount: photos.drafts.count,
                        openPhotos: { selectedSection = .photos },
                        openTalks: { selectedSection = .talks }
                    )
                case .photos:
                    PhotosScreen(store: photos)
                case .blog, .talks:
                    WritingScreen(section: section, overview: overview)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("个人中心", systemImage: account.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle") {
                        showingAccount = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityHint("登录、外观和博客设置")
                }
            }
        }
    }
}
