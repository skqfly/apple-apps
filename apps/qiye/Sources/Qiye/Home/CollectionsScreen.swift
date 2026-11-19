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
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                        count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    Button { open(.photos) } label: {
                        tile("图片", symbol: "photo.on.rectangle", count: photos.photos.count, tint: Color.appAccent)
                    }
                    .accessibilityIdentifier("collection-photos")
                    Button { open(.talks) } label: {
                        tile("说说", symbol: "text.bubble", count: library.allTalks().count, tint: Color.appAccent)
                    }
                    .accessibilityIdentifier("collection-talks")
                    directoryTile(.projects, count: directory.projects.count, tint: Color.appAccent)
                    directoryTile(.friends, count: directory.friends.count, tint: Color.appAccent)
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

                if !recentTalks.isEmpty {
                    recentTalksSection
                }
            }
            .padding(.horizontal, AppPageLayout.horizontalInset)
            .padding(.top, AppPageLayout.topInset)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .appPageBackground()
        .appNavigationTitle("首页")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("发布与同步", systemImage: "tray.and.arrow.up", action: showStudio)
                    Button("个人中心", systemImage: "person.crop.circle", action: showAccount)
                } label: {
                    ToolbarActionIcon("更多", systemImage: "ellipsis")
                }
            }
            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if canEditDirectory {
                        Button("添加项目", systemImage: DirectoryKind.projects.symbol) { newEntry = .projects }
                        Button("添加友链", systemImage: DirectoryKind.friends.symbol) { newEntry = .friends }
                    } else {
                        Button("登录 GitHub 以添加", systemImage: "person.crop.circle", action: showAccount)
                    }
                } label: {
                    ToolbarActionIcon("添加", systemImage: "plus")
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
        .plannerSurface(tint: Color.appAccent.opacity(0.05))
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    private var recentTalks: [TalkPost] {
        Array(library.allTalks()
            .filter { !$0.description.isEmpty }
            .sorted { $0.date > $1.date }
            .prefix(3))
    }

    private var recentTalksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近说说").font(.caption).foregroundStyle(.secondary)
            ForEach(recentTalks) { talk in
                Button { open(.talks) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "text.bubble")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(talk.description)
                                .font(.subheadline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(talk.date, format: .dateTime.month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CollectionPressStyle())
                .accessibilityLabel("说说：\(talk.description)")
            }
        }
        .padding(16)
        .plannerSurface(tint: Color.appAccent.opacity(0.05))
        .frame(maxWidth: .infinity, alignment: .leading)
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
    func plannerSurface(tint: Color = .clear, radius: CGFloat = 19) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return background(tint, in: shape)
            .background(.thinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
    }
}
