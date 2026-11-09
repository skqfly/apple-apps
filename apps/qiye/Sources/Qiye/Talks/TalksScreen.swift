import SwiftUI

@MainActor
struct TalksScreen: View {
    @State private var store: TalksStore
    let pending: PendingChangesStore
    let photos: PhotoLibraryStore
    let library: ContentLibraryStore
    let canPublish: Bool
    let authorName: String
    let avatarURL: URL?
    @State private var composer = false
    @State private var editing: TalkPost?
    @State private var viewing: TalkGallerySelection?
    @State private var deleting: TalkPost?
    @State private var purging: TalkPost?
    @State private var notice: String?

    init(repository: GitHubRepository, pending: PendingChangesStore, photos: PhotoLibraryStore,
         library: ContentLibraryStore, canPublish: Bool, authorName: String, avatarURL: URL?) {
        _store = State(initialValue: TalksStore(repository: repository))
        self.pending = pending
        self.photos = photos
        self.library = library
        self.canPublish = canPublish
        self.authorName = authorName
        self.avatarURL = avatarURL
    }

    private var posts: [TalkPost] {
        let query = store.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.allTalks().filter { query.isEmpty || $0.description.localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let notice {
                    Text(notice)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .liquidGlassCapsule(interactive: false)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let error = store.error {
                    ContentStatus(message: error) { await store.refresh(); library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot) }
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                if posts.isEmpty {
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
                                restore: { restore(post) },
                                purge: { purging = post },
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
        .background(Color.appBackground)
        .navigationTitle("说说")
        .searchable(text: $store.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索说说")
        .toolbar { composeToolbar }
        .sheet(isPresented: $composer) {
            TalkEditorSheet(post: nil, library: library) { showNotice("已保存到未发表") }
        }
        .sheet(item: $editing) { post in
            TalkEditorSheet(post: post, library: library) { showNotice("已保存修改；公开内容将在首页推送后更新") }
        }
        .fullScreenCover(item: $viewing) { selection in
            MediaViewer(items: selection.items, initialIndex: selection.index)
        }
        .confirmationDialog("移到已删除？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("移到已删除", role: .destructive) {
                if let post = deleting { change(post, to: .deleted) }
                deleting = nil
            }
        } message: { Text("内容会保留在列表中并标为已删除，可以随时恢复。") }
        .confirmationDialog("彻底删除这条说说？", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } }), titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) {
                if let post = purging {
                    do {
                        try library.purgeTalk(post)
                        showNotice("已彻底删除")
                    } catch {
                        showNotice(error.localizedDescription)
                    }
                }
                purging = nil
            }
        } message: { Text("本机保留的内容将被彻底移除，无法再恢复。") }
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

    @ToolbarContentBuilder
    private var composeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { composeButton }
    }

    private var composeButton: some View {
        Button {
            Haptics.light()
            composer = true
        } label: {
            Image(systemName: "square.and.pencil")
        }
        .buttonStyle(AppleNavCircleButtonStyle(size: 34, isAccent: true))
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
            showNotice(state == .published ? "已加入发表队列，去首页推送即可" : "已设为\(state.title)")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    private func restore(_ post: TalkPost) {
        do {
            try library.restoreTalk(post)
            showNotice("已恢复到未发表")
        } catch {
            showNotice(error.localizedDescription)
        }
    }
}

private struct TalkGallerySelection: Identifiable {
    let id = UUID()
    let post: TalkPost
    let index: Int
    var items: [MediaViewerItem] {
        post.images.enumerated().compactMap { offset, image in
            guard let url = image.originalURL else { return nil }
            return MediaViewerItem(id: "\(post.id)-\(offset)", url: url, previewURL: image.url)
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
    let restore: () -> Void
    let purge: () -> Void
    let openImage: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: avatarURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Image(systemName: "person.fill").resizable().scaledToFit().padding(10).foregroundStyle(Color.appAccent).background(Color.appAccent.opacity(0.10)) }
            }
            .frame(width: 42, height: 42)
            .clipShape(.rect(cornerRadius: 9))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 9) {
                Text(authorName.isEmpty ? "skqfly" : authorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appAccent)

                if !post.description.isEmpty {
                    Text(post.description)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TalkImageGrid(images: post.images, open: openImage)

                // Bottom row: Status badge + date on the left, action menu on the right
                HStack(alignment: .center, spacing: 8) {
                    statusBadge(for: state)

                    Text(post.date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    actionMenu
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .liquidGlassCard(cornerRadius: 18)
        .opacity(state == .deleted ? 0.75 : 1)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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
            if state == .deleted {
                Button("恢复到未发表", systemImage: "arrow.uturn.backward", action: restore)
                Button("彻底删除", systemImage: "trash.slash", role: .destructive, action: purge)
            } else {
                Button("编辑", systemImage: "pencil", action: edit)
                if state == .published {
                    Button("下架到未发表", systemImage: "arrow.down.circle") { changeState(.unpublished) }
                } else {
                    Button("发表", systemImage: "arrow.up.circle") { changeState(.published) }
                }
                Button("移到已删除", systemImage: "trash", role: .destructive, action: delete)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.appAccent)
                .liquidGlassCircle(size: 32)
        }
        .accessibilityLabel("说说操作")
        .accessibilityIdentifier("talk-actions-\(post.id)")
    }
}

struct TalkImageGrid: View {
    let images: [TalkImage]
    let open: (Int) -> Void
    private var columnCount: Int { images.count == 4 ? 2 : min(3, images.count) }

    var body: some View {
        if images.count == 1, let image = images.first {
            tile(image, index: 0, ratio: min(1.5, max(0.75, image.aspectRatio)))
                .frame(maxWidth: 250, alignment: .leading)
        } else if !images.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columnCount), alignment: .leading, spacing: 5) {
                ForEach(Array(images.prefix(9).enumerated()), id: \.offset) { index, image in
                    tile(image, index: index, ratio: 1)
                }
            }
            .frame(maxWidth: images.count == 4 || images.count == 2 ? 230 : .infinity, alignment: .leading)
        }
    }

    private func tile(_ image: TalkImage, index: Int, ratio: Double) -> some View {
        Button { open(index) } label: {
            Color.clear.aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    if let url = image.url {
                        Group {
                            if url.isFileURL { LocalPhotoImage(url: url) }
                            else {
                                AsyncImage(url: url) { phase in
                                    if let loaded = phase.image { loaded.resizable().scaledToFill() }
                                    else { Color.secondary.opacity(0.12).overlay { Image(systemName: "photo").foregroundStyle(.secondary) } }
                                }
                            }
                        }.allowsHitTesting(false)
                    }
                }
                .clipped().clipShape(.rect(cornerRadius: 3)).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看第\(index + 1)张图片")
        .accessibilityIdentifier("talk-image-\(index)")
    }
}
