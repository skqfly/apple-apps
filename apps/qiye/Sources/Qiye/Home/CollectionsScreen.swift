import SwiftUI

@MainActor
struct CollectionsScreen: View {
    let blog: BlogStore
    let photos: PhotoLibraryStore
    let library: ContentLibraryStore
    let open: (SiteSection) -> Void
    let showAccount: () -> Void
    let showStudio: () -> Void
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
            VStack(alignment: .leading, spacing: 26) {
                Button { open(.photos) } label: { allContentCard }
                    .buttonStyle(CollectionPressStyle())

                VStack(spacing: 12) {
                    CollectionHeading(title: "置顶收藏")
                    HStack(spacing: 12) {
                        collection(title: "文章", detail: "\(blog.posts.count) 篇记录", artwork: "paperGeometry", section: .blog)
                        collection(title: "说说", detail: "\(library.allTalks().count) 个瞬间", artwork: "eveningCoast", section: .talks)
                    }
                }

                VStack(spacing: 12) {
                    CollectionHeading(title: "我的空间")
                    HStack(spacing: 12) {
                        NavigationLink {
                            SiteDirectoryScreen(store: directory, kind: .projects)
                        } label: {
                            collectionCard(title: "项目", detail: "\(directory.projects.count) 个正在探索的想法", artwork: "glassCabinet", symbol: "square.stack.3d.up")
                        }
                        .accessibilityIdentifier("collection-projects")
                        NavigationLink {
                            SiteDirectoryScreen(store: directory, kind: .friends)
                        } label: {
                            collectionCard(title: "友链", detail: "\(directory.friends.count) 位同行的人", artwork: "sunlitWalk", symbol: "person.2")
                        }
                        .accessibilityIdentifier("collection-friends")
                    }
                    .buttonStyle(CollectionPressStyle())
                }

                if !blog.posts.isEmpty {
                    VStack(spacing: 12) {
                        CollectionHeading(title: "最近的文字", detail: "\(blog.posts.count) 篇")
                        ForEach(blog.posts.prefix(3)) { post in
                            NavigationLink { BlogDetailScreen(post: post) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "doc.text").font(.title3)
                                        .frame(width: 48, height: 56)
                                        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(post.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        Text(post.date, format: .dateTime.year().month().day())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(14).collectionSurface(radius: 18)
                            }
                            .buttonStyle(CollectionPressStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    Button("发布与同步", systemImage: "tray.and.arrow.up", action: showStudio)
                    Button("个人中心", systemImage: "person.crop.circle", action: showAccount)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(AppleNavCircleButtonStyle(size: 36))
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

    private var allContentCard: some View {
        HStack(spacing: 18) {
            ZStack {
                CollectionArtwork(name: "coast")
                    .frame(width: 84, height: 112).clipShape(.rect(cornerRadius: 9))
                    .rotationEffect(.degrees(-14)).offset(x: -18, y: 4)
                CollectionArtwork(name: "mountainView")
                    .frame(width: 84, height: 112).clipShape(.rect(cornerRadius: 9))
                    .rotationEffect(.degrees(10)).offset(x: 14, y: -3)
                CollectionArtwork(name: "eveningCoast")
                    .frame(width: 84, height: 112).clipShape(.rect(cornerRadius: 9))
                    .rotationEffect(.degrees(-3))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
            }
            .frame(width: 140, height: 152)
            VStack(alignment: .leading, spacing: 8) {
                Text("光影收藏").font(.title3.weight(.semibold))
                Text("\(photos.photos.count) 张照片").font(.subheadline).foregroundStyle(.secondary)
                Label("打开相册", systemImage: "arrow.up.right")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .collectionSurface(radius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("collection-photos")
    }

    private func collection(title: String, detail: String, artwork: String, section: SiteSection) -> some View {
        Button { open(section) } label: {
            collectionCard(title: title, detail: detail, artwork: artwork, symbol: section.symbolName)
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityIdentifier("collection-\(section.rawValue)")
    }

    private func collectionCard(title: String, detail: String, artwork: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CollectionArtwork(name: artwork)
                .frame(height: 152)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: symbol).font(.title3)
                        .foregroundStyle(.white).padding(10)
                        .background(.black.opacity(0.3), in: .rect(cornerRadius: 12)).padding(12)
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.primary)
        .collectionSurface(radius: 20).clipShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
