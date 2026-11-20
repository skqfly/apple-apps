import SwiftUI

@MainActor
struct TalksScreen: View {
    @Bindable var store: TalksStore
    let pending: PendingChangesStore
    let photos: PhotoLibraryStore
    let library: ContentLibraryStore
    let canPublish: Bool
    let authorName: String
    let avatarURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var composer = false
    @State private var editing: TalkPost?
    @State private var viewing: TalkGallerySelection?
    @State private var deleting: TalkPost?
    @State private var notice: String?
    @State private var statusFilter: ContentStatusFilter?
    @Namespace private var imageZoom

    init(store: TalksStore, pending: PendingChangesStore, photos: PhotoLibraryStore,
         library: ContentLibraryStore, canPublish: Bool, authorName: String, avatarURL: URL?) {
        self.store = store
        self.pending = pending
        self.photos = photos
        self.library = library
        self.canPublish = canPublish
        self.authorName = authorName
        self.avatarURL = avatarURL
    }

    private var searchTerm: String { store.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var posts: [TalkPost] {
        let query = searchTerm
        let visible = statusFilter.map { library.talks(in: $0) } ?? library.visibleTalks()
        return visible.filter { query.isEmpty || $0.description.localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                filters
                if let notice {
                    Text(notice)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .liquidGlassCapsule(interactive: false)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
                }
                if let error = store.error {
                    ContentStatus(message: error) { await store.refresh(); library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot) }
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                if posts.isEmpty && !searchTerm.isEmpty {
                    ContentUnavailableView.search(text: searchTerm)
                        .padding(.vertical, 24)
                } else if posts.isEmpty, let statusFilter {
                    ContentUnavailableView("暂无\(statusFilter.title)的说说", systemImage: "text.bubble")
                        .padding(.vertical, 36)
                } else if posts.isEmpty {
                    ContentUnavailableView(
                        "这里还没有说说",
                        systemImage: "text.bubble",
                        description: Text("点击右上角写说说，记录生活中的点滴。")
                    )
                    .padding(.vertical, 60)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(posts) { post in
                            let state = library.stateOfTalk(post.id)
                            TalkTimelineRow(
                                post: post,
                                authorName: authorName,
                                avatarURL: avatarURL,
                                state: state,
                                canManage: canPublish,
                                edit: { editing = post },
                                changeState: { newState in change(post, to: newState) },
                                delete: { deleting = post },
                                imageZoom: imageZoom,
                                openImage: { index in viewing = TalkGallerySelection(post: post, index: index) }
                            )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 96)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .appPageBackground()
        .appNavigationTitle("说说")
        .searchable(text: $store.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索说说")
        .toolbar { composeToolbar }
        .sheet(isPresented: $composer) {
            TalkEditorSheet(post: nil, library: library) { showNotice("已保存到未发表") }
        }
        .sheet(item: $editing) { post in
            TalkEditorSheet(post: post, library: library) { showNotice("已保存修改；公开内容将在“发布与同步”中推送后更新") }
        }
        .fullScreenCover(item: $viewing) { selection in
            MediaViewer(items: selection.items, initialIndex: selection.initialIndex)
                .collectionZoomDestination(id: selection.sourceID, namespace: imageZoom, enabled: !reduceMotion)
        }
        .confirmationDialog("移到回收站？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("移到回收站", role: .destructive) {
                if let post = deleting { change(post, to: .deleted) }
                deleting = nil
            }
        } message: { Text("可以在个人中心的回收站恢复说说。") }
        .task {
            library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot)
            await store.loadIfNeeded()
            library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot)
        }
        .refreshable {
            await store.refresh()
            library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot)
        }
        .onChange(of: pending.committedRevision) {
            Task {
                await store.refresh()
                library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot)
            }
        }
    }

    private var filters: some View {
        CollectionFilterBar {
            filterChip(nil)
            filterChip(.published)
            filterChip(.unpublished)
        }
    }

    private func filterChip(_ status: ContentStatusFilter?) -> some View {
        CollectionFilterChip(title: status?.title ?? "全部", isSelected: statusFilter == status) {
            statusFilter = status
        }
        .accessibilityIdentifier("talk-filter-\(status?.rawValue ?? "all")")
    }

    @ToolbarContentBuilder
    private var composeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { composeButton }
    }

    private var composeButton: some View {
        Button {
            Haptics.light()
            composer = true
        } label: {
            ToolbarActionIcon("写说说", systemImage: "plus.bubble")
        }
        .accessibilityLabel("写说说")
        .accessibilityIdentifier("compose-talk")
        .disabled(pending.isCommitting)
    }

    private func showNotice(_ text: String) {
        withAnimation(.snappy(duration: 0.25)) { notice = text }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25)) {
                if notice == text { notice = nil }
            }
        }
    }

    private func change(_ post: TalkPost, to state: ContentStatusFilter) {
        do {
            try library.setTalkState(post, to: state)
            switch state {
            case .published: showNotice("已加入发表队列，可从首页右上角的「更多」进入「发布与同步」")
            case .unpublished: showNotice("已设为未发表")
            case .deleted: showNotice("已移到回收站")
            }
        } catch {
            showNotice(error.localizedDescription)
        }
    }

}

private struct TalkGallerySelection: Identifiable {
    let id = UUID()
    let post: TalkPost
    let index: Int
    var sourceID: String { Self.sourceID(postID: post.id, index: index) }
    var initialIndex: Int { items.firstIndex { $0.id == sourceID } ?? 0 }

    static func sourceID(postID: String, index: Int) -> String { "\(postID)-\(index)" }

    var items: [MediaViewerItem] {
        post.images.enumerated().compactMap { offset, image in
            guard let url = image.originalURL ?? image.url else { return nil }
            return MediaViewerItem(id: Self.sourceID(postID: post.id, index: offset), url: url, previewURL: image.url)
        }
    }
}

private struct TalkTimelineRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let post: TalkPost
    let authorName: String
    let avatarURL: URL?
    let state: ContentStatusFilter
    let canManage: Bool
    let edit: () -> Void
    let changeState: (ContentStatusFilter) -> Void
    let delete: () -> Void
    let imageZoom: Namespace.ID
    let openImage: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: "person.fill").resizable().scaledToFit().padding(8).foregroundStyle(.secondary) }
                }
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06), in: Circle()).clipShape(Circle())
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(authorName.isEmpty ? "skqfly" : authorName).font(.subheadline.weight(.semibold))
                    Text(post.date, format: .dateTime.year().month().day())
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                actionMenu
            }
            if !post.description.isEmpty {
                Text(post.description).font(.body).foregroundStyle(.primary)
                    .lineSpacing(5).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TalkImageGrid(images: post.images, postID: post.id, imageZoom: imageZoom, open: openImage)
            HStack {
                statusBadge(for: state)
                Spacer()
                if !post.images.isEmpty {
                    Label("\(post.images.count)", systemImage: "square.on.square")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(18)
        .collectionSurface(radius: 22)
        .padding(.horizontal, 18).padding(.vertical, 7)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("talk-row-\(post.id)")
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(for state: ContentStatusFilter) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor(for: state))
                .frame(width: 5.5, height: 5.5)

            Text(state.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(badgeColor(for: state))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            badgeColor(for: state).opacity(colorScheme == .dark ? 0.18 : 0.10),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(badgeColor(for: state).opacity(colorScheme == .dark ? 0.35 : 0.22), lineWidth: 0.6)
        }
        .accessibilityLabel("状态：\(state.title)")
        .accessibilityIdentifier("talk-status-badge-\(post.id)")
    }

    private func badgeColor(for state: ContentStatusFilter) -> Color {
        switch state {
        case .published:
            return colorScheme == .dark
                ? Color(red: 0.38, green: 0.86, blue: 0.66)
                : Color(red: 0.12, green: 0.56, blue: 0.40)
        case .unpublished:
            return colorScheme == .dark
                ? Color(red: 0.98, green: 0.68, blue: 0.28)
                : Color(red: 0.90, green: 0.50, blue: 0.10)
        case .deleted:
            return colorScheme == .dark
                ? Color(red: 0.95, green: 0.45, blue: 0.45)
                : Color(red: 0.82, green: 0.28, blue: 0.28)
        }
    }

    // MARK: - Action Menu

    private var actionMenu: some View {
        Menu {
            Button("编辑", systemImage: "pencil", action: edit)
            if state == .published {
                Button("下架到未发表", systemImage: "arrow.down.circle") { changeState(.unpublished) }
            } else {
                Button("发表", systemImage: "arrow.up.circle") { changeState(.published) }
            }
            Button("移到回收站", systemImage: "trash", role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 24)
                .background(Color.primary.opacity(0.055), in: Capsule())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("说说操作")
        .accessibilityIdentifier("talk-actions-\(post.id)")
    }
}

private struct TalkImageGrid: View {
    let images: [TalkImage]
    let postID: String
    let imageZoom: Namespace.ID
    let open: (Int) -> Void
    @Environment(\.offlineWebsite) private var offlineWebsite
    private var columnCount: Int { images.count == 4 ? 2 : min(3, images.count) }

    var body: some View {
        if images.count == 1, let image = images.first {
            tile(image, index: 0, ratio: min(1.5, max(0.75, image.aspectRatio)))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !images.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columnCount), alignment: .leading, spacing: 5) {
                ForEach(Array(images.prefix(9).enumerated()), id: \.offset) { index, image in
                    tile(image, index: index, ratio: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tile(_ image: TalkImage, index: Int, ratio: Double) -> some View {
        Button { open(index) } label: {
            Color.appSurface.aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    if let url = image.url {
                        Group {
                            if url.isFileURL { LocalPhotoImage(url: url) }
                            else if let local = offlineWebsite?.imageURL(for: url) { LocalPhotoImage(url: local) }
                            else {
                                AsyncImage(url: url) { phase in
                                    if let loaded = phase.image { loaded.resizable().scaledToFill() }
                                    else { Color.secondary.opacity(0.12).overlay { Image(systemName: "photo").foregroundStyle(.secondary) } }
                                }
                            }
                        }.allowsHitTesting(false)
                    }
                }
                .clipped().clipShape(.rect(cornerRadius: 9)).contentShape(.rect)
                .collectionZoomSource(id: TalkGallerySelection.sourceID(postID: postID, index: index), namespace: imageZoom)
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel("查看第\(index + 1)张图片")
        .accessibilityIdentifier("talk-image-\(index)")
    }
}
