import SwiftUI

@MainActor
struct CollectionsScreen: View {
    let blog: BlogStore
    let photos: PhotoLibraryStore
    let library: ContentLibraryStore
    let open: (SiteSection) -> Void
    let showAccount: () -> Void
    let showStudio: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var directory: SiteDirectoryStore
    @State private var screenshotDestination: DirectoryKind?

    init(blog: BlogStore, photos: PhotoLibraryStore, library: ContentLibraryStore,
         repository: GitHubRepository, open: @escaping (SiteSection) -> Void,
         showAccount: @escaping () -> Void, showStudio: @escaping () -> Void) {
        self.blog = blog
        self.photos = photos
        self.library = library
        self.open = open
        self.showAccount = showAccount
        self.showStudio = showStudio
        _directory = State(initialValue: SiteDirectoryStore(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                        count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    Button { open(.photos) } label: {
                        tile("图片", symbol: "photo.on.rectangle", count: "\(photos.photos.count) 张")
                    }
                    .accessibilityIdentifier("collection-photos")
                    Button { open(.talks) } label: {
                        tile("说说", symbol: "text.bubble", count: "\(library.allTalks().count) 条")
                    }
                    NavigationLink {
                        SiteDirectoryScreen(store: directory, kind: .projects)
                    } label: {
                        tile("项目", symbol: "square.stack.3d.up", count: "\(directory.projects.count) 个")
                    }
                    .accessibilityIdentifier("collection-projects")
                    NavigationLink {
                        SiteDirectoryScreen(store: directory, kind: .friends)
                    } label: {
                        tile("友链", symbol: "person.2", count: "\(directory.friends.count) 个")
                    }
                    .accessibilityIdentifier("collection-friends")
                }
                .buttonStyle(CollectionPressStyle())

                if let latest = blog.posts.first {
                    NavigationLink {
                        BlogDetailScreen(post: latest)
                    } label: {
                        latestBlog(latest)
                    }
                    .buttonStyle(CollectionPressStyle())
                }
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("发布与同步", systemImage: "tray.and.arrow.up", action: showStudio)
                    Button("个人中心", systemImage: "person.crop.circle", action: showAccount)
                } label: {
                    Label("更多", systemImage: "ellipsis")
                }
            }
        }
        .task {
            await blog.loadIfNeeded()
            await directory.refresh()
        }
        .refreshable {
            await blog.refresh()
            await directory.refresh()
            await photos.refresh()
            library.syncPhotos(photos.photos, authoritative: photos.hasRemoteSnapshot)
        }
        #if DEBUG
        .navigationDestination(item: $screenshotDestination) { kind in
            SiteDirectoryScreen(store: directory, kind: kind)
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--projects") { screenshotDestination = .projects }
            if arguments.contains("--friends") { screenshotDestination = .friends }
        }
        #endif
    }

    private func latestBlog(_ post: BlogPost) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("最新博客", systemImage: "doc.text")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appAccent)
                Text(post.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if post.date != .distantPast {
                    Text(post.date, format: .dateTime.year().month().day())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .collectionSurface(radius: 20)
        .contentShape(.rect(cornerRadius: 20))
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开全文")
    }

    private func tile(_ title: String, symbol: String, count: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.appAccent)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.medium))
            Text(count)
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .collectionSurface(radius: 20)
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
