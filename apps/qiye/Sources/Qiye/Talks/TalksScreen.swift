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
    @State private var status: ContentStatusFilter = .published
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
        return library.talks(in: status).filter { query.isEmpty || $0.description.localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ContentStatusPicker(selection: $status, counts: Dictionary(uniqueKeysWithValues: ContentStatusFilter.allCases.map { ($0, library.talks(in: $0).count) }))
                .accessibilityIdentifier("talk-status-picker")
                .padding(.horizontal, 18).padding(.vertical, 14)
                if let notice { Text(notice).font(.caption).foregroundStyle(Color.appAccent).padding(.horizontal).padding(.bottom, 12) }
                if let error = store.error {
                    ContentStatus(message: error) { await store.refresh(); library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot) }.padding(.horizontal)
                }
                if posts.isEmpty {
                    ContentUnavailableView(status == .deleted ? "回收站是空的" : "这里还没有说说", systemImage: status == .deleted ? "trash" : "text.bubble", description: Text(status == .unpublished ? "新建和下架的说说会保存在这里。" : ""))
                        .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(posts) { post in
                            TalkTimelineRow(post: post, authorName: authorName, avatarURL: avatarURL, state: status,
                                canManage: canPublish, edit: { editing = post },
                                changeState: { newState in change(post, to: newState) },
                                delete: { deleting = post }, restore: { restore(post) }, purge: { purging = post },
                                openImage: { index in viewing = TalkGallerySelection(post: post, index: index) })
                        }
                    }
                }
            }
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(Color.appSurface)
        .navigationTitle("说说")
        .searchable(text: $store.query, prompt: "搜索说说")
        .toolbar { composeToolbar }
        .sheet(isPresented: $composer) {
            TalkEditorSheet(post: nil, library: library) { status = .unpublished; notice = "已保存到未发表" }
        }
        .sheet(item: $editing) { post in
            TalkEditorSheet(post: post, library: library) { notice = "已保存修改；公开内容将在首页推送后更新" }
        }
        .fullScreenCover(item: $viewing) { selection in
            MediaViewer(items: selection.items, initialIndex: selection.index)
        }
        .confirmationDialog("移到已删除？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("移到已删除", role: .destructive) { if let post = deleting { change(post, to: .deleted) }; deleting = nil }
        } message: { Text("内容会保留在回收站，可以恢复到未发表。") }
        .confirmationDialog("彻底删除这条说说？", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } }), titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) {
                if let post = purging { do { try library.purgeTalk(post); notice = "已彻底删除" } catch { notice = error.localizedDescription } }
                purging = nil
            }
        } message: { Text("本机保留的内容将被移除，无法从回收站恢复。") }
        .task { library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot); await store.loadIfNeeded(); library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot) }
        .refreshable { await store.refresh(); library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot) }
        .onChange(of: pending.committedRevision) { Task { await store.refresh(); library.syncTalks(store.posts, authoritative: store.hasRemoteSnapshot) } }
    }

    @ToolbarContentBuilder
    private var composeToolbar: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarTrailing) { composeButton }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { composeButton }
        }
    }
    private var composeButton: some View {
        Button { composer = true } label: {
            Image(systemName: "square.and.pencil").font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44).modifier(ProfileGlassRing())
        }
        .buttonStyle(.plain).accessibilityLabel("写说说").accessibilityIdentifier("compose-talk")
        .disabled(pending.isCommitting)
    }

    private func change(_ post: TalkPost, to state: ContentStatusFilter) {
        do { try library.setTalkState(post, to: state); notice = state == .published ? "已加入发表队列，去首页推送即可" : "已移到\(state.title)" }
        catch { notice = error.localizedDescription }
    }
    private func restore(_ post: TalkPost) {
        do { try library.restoreTalk(post); notice = "已恢复到未发表" }
        catch { notice = error.localizedDescription }
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
            .frame(width: 42, height: 42).clipShape(.rect(cornerRadius: 9)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                Text(authorName.isEmpty ? "skqfly" : authorName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appAccent)
                if !post.description.isEmpty { Text(post.description).font(.body).foregroundStyle(.primary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                TalkImageGrid(images: post.images, open: openImage)
                HStack {
                    Text(post.date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        if state == .deleted {
                            Button("恢复到未发表", systemImage: "arrow.uturn.backward", action: restore)
                            Button("彻底删除", systemImage: "trash.slash", role: .destructive, action: purge)
                        } else {
                            Button("编辑", systemImage: "pencil", action: edit)
                            Button(state == .published ? "下架到未发表" : "发表", systemImage: state == .published ? "arrow.down.circle" : "arrow.up.circle") { changeState(state == .published ? .unpublished : .published) }
                            Button("移到已删除", systemImage: "trash", role: .destructive, action: delete)
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.bold)).foregroundStyle(Color.appAccent)
                            .frame(width: 42, height: 30).background(Color.appAccent.opacity(0.07), in: .rect(cornerRadius: 7))
                    }
                    .accessibilityLabel("说说操作").accessibilityIdentifier("talk-actions-\(post.id)")
                }
                .padding(.top, 3)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 20)
        .background(Color.appSurface)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 74) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("talk-row-\(post.id)")
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
