import SwiftUI

@MainActor
struct CollectionsScreen: View {
    let blog: BlogStore
    let photos: PhotoLibraryStore
    let library: ContentLibraryStore
    let canEditDirectory: Bool
    let open: (SiteSection) -> Void
    let showAccount: () -> Void
    let showStudio: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var directory: SiteDirectoryStore
    @State private var newEntry: DirectoryKind?
    #if DEBUG
    @State private var screenshotDestination: DirectoryKind?
    #endif

    init(blog: BlogStore, photos: PhotoLibraryStore, library: ContentLibraryStore,
         repository: GitHubRepository, canEditDirectory: Bool, open: @escaping (SiteSection) -> Void,
         showAccount: @escaping () -> Void, showStudio: @escaping () -> Void) {
        self.blog = blog
        self.photos = photos
        self.library = library
        self.canEditDirectory = canEditDirectory
        self.open = open
        self.showAccount = showAccount
        self.showStudio = showStudio
        _directory = State(initialValue: SiteDirectoryStore(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(Date.now, format: .dateTime.month().day().weekday(.wide))
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 4)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                        count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    Button { open(.photos) } label: {
                        tile("图片", symbol: "photo.on.rectangle", count: photos.photos.count, tint: .blue)
                    }
                    .accessibilityIdentifier("collection-photos")
                    Button { open(.talks) } label: {
                        tile("说说", symbol: "text.bubble", count: library.allTalks().count, tint: .indigo)
                    }
                    .accessibilityIdentifier("collection-talks")
                    directoryTile(.projects, count: directory.projects.count, tint: .indigo)
                    directoryTile(.friends, count: directory.friends.count, tint: .purple)
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
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack(alignment: .top) {
                Color.appBackground
                LinearGradient(colors: [.indigo.opacity(0.12), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
                    .frame(height: 430)
            }
            .ignoresSafeArea()
        }
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    if canEditDirectory {
                        Button("添加项目", systemImage: DirectoryKind.projects.symbol) { newEntry = .projects }
                        Button("添加友链", systemImage: DirectoryKind.friends.symbol) { newEntry = .friends }
                    } else {
                        Button("登录 GitHub 以添加", systemImage: "person.crop.circle", action: showAccount)
                    }
                } label: {
                    ActionIcon("添加", systemImage: "plus")
                }

                Menu {
                    Button("发布与同步", systemImage: "tray.and.arrow.up", action: showStudio)
                    Button("个人中心", systemImage: "person.crop.circle", action: showAccount)
                } label: {
                    ActionIcon("更多", systemImage: "ellipsis")
                }
            }
        }
        .sheet(item: $newEntry) { kind in
            DirectoryEditor(store: directory, kind: kind)
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
            SiteDirectoryScreen(store: directory, kind: kind, canEdit: canEditDirectory)
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--projects") { screenshotDestination = .projects }
            if arguments.contains("--friends") { screenshotDestination = .friends }
        }
        #endif
    }

    private func directoryTile(_ kind: DirectoryKind, count: Int, tint: Color) -> some View {
        NavigationLink {
            SiteDirectoryScreen(store: directory, kind: kind, canEdit: canEditDirectory)
        } label: {
            tile(kind.title, symbol: kind.symbol, count: count, tint: tint)
        }
        .accessibilityIdentifier("collection-\(kind.rawValue)")
    }

    private func latestBlog(_ post: BlogPost) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("最新博客").font(.caption).foregroundStyle(.secondary)
                Text(post.title).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .plannerSurface(tint: .indigo.opacity(0.05))
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    private func tile(_ title: String, symbol: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 5)
                Text(count.formatted())
                    .font(.title2.weight(.semibold).monospacedDigit())
            }
            .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(Color.primary)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .plannerSurface(tint: tint.opacity(0.10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(count.formatted())
    }
}

extension View {
    func plannerSurface(tint: Color = .clear) -> some View {
        let shape = RoundedRectangle(cornerRadius: 19)
        return background(tint, in: shape)
            .background(.thinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
    }
}
