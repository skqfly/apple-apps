import SwiftUI

@MainActor
struct TalksScreen: View {
    @State private var store: TalksStore
    @State private var showingComposer = false
    @State private var editing: TalkPost?
    let pending: PendingChangesStore
    let photos: PhotoLibraryStore
    let canPublish: Bool

    init(repository: GitHubRepository, pending: PendingChangesStore, photos: PhotoLibraryStore, canPublish: Bool) {
        _store = State(initialValue: TalksStore(repository: repository))
        self.pending = pending
        self.photos = photos
        self.canPublish = canPublish
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if !canPublish {
                    Label("连接 GitHub 后可以发布新的说说", systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.error {
                    ContentStatus(message: error) { await store.refresh() }
                }
                if store.isLoading && store.posts.isEmpty {
                    ProgressView("正在读取说说…").frame(maxWidth: .infinity).padding(.vertical, 50)
                } else if store.filteredPosts.isEmpty && (store.error == nil || !store.posts.isEmpty) {
                    ContentUnavailableView(
                        store.query.isEmpty ? "还没有说说" : "未找到说说",
                        systemImage: "text.bubble",
                        description: Text(store.query.isEmpty ? "新的想法，值得被记录。" : "换一个关键词再试试。")
                    )
                } else {
                    ForEach(store.filteredPosts) { post in
                        TalkCard(post: post, canPublish: canPublish) {
                            editing = post
                        } onUnpublish: {
                            pending.stageUnpublishTalk(talkID: post.id)
                        } onDelete: {
                            pending.stageDeleteTalk(talkID: post.id, imageSources: post.images.map(\.src))
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle("说说")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.query, prompt: "搜索说说")
        .toolbar {
            if canPublish {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("写说说", systemImage: "square.and.pencil") { showingComposer = true }
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            NewTalkSheet(pending: pending, photos: photos) { Task { await store.refresh() } }
        }
        .sheet(item: $editing) { post in
            TalkEditorSheet(post: post, pending: pending, photos: photos) { Task { await store.refresh() } }
        }
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
        .onChange(of: pending.committedRevision) { Task { await store.refresh() } }
    }
}

private struct TalkCard: View {
    let post: TalkPost
    let canPublish: Bool
    let onEdit: () -> Void
    let onUnpublish: () -> Void
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var confirmsDelete = false
    private let actionWidth: CGFloat = 78

    var body: some View {
        ZStack(alignment: .trailing) {
            if canPublish {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    action("编辑", "pencil", .appAccent, onEdit)
                    action("下架", "arrow.down.circle", .orange) { close(); onUnpublish() }
                    action("删除", "trash", .red) { confirmsDelete = true }
                }
            }
            card
                .offset(x: offset)
                .gesture(canPublish ? drag : nil)
                .onTapGesture {
                    if offset != 0 { close() }
                    else if canPublish { onEdit() }
                }
        }
        .clipped()
        .confirmationDialog("删除这条说说？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { close(); onDelete() }
        } message: { Text("删除会暂存到首页，一键推送后从网站和仓库移除。") }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(0, max(-actionWidth * 3, value.translation.width + (offset == 0 ? 0 : -actionWidth * 3)))
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    offset = value.translation.width < -actionWidth ? -actionWidth * 3 : 0
                }
            }
    }

    private func close() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { offset = 0 }
    }

    private func action(_ title: String, _ symbol: String, _ tint: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title).font(.caption2)
            }
            .foregroundStyle(.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(tint)
        }
        .buttonStyle(.plain)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(post.date, format: .dateTime.year().month().day())
                .font(.caption).foregroundStyle(.secondary)
            MarkdownBlocks(post.description)
            TalkImageGrid(images: post.images)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(.rect)
    }
}

struct TalkImageGrid: View {
    let images: [TalkImage]

    var body: some View {
        if !images.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { entry in
                    if let url = entry.element.url, let original = entry.element.originalURL {
                        Link(destination: original) {
                            Color.clear
                                .frame(height: 170)
                                .overlay {
                                    GeometryReader { geometry in
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case let .success(image): image.resizable().scaledToFill()
                                            case .failure: Image(systemName: "photo").foregroundStyle(.secondary)
                                            default: ProgressView()
                                            }
                                        }
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                    }
                                }
                            .clipped()
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityLabel(entry.element.alt ?? "说说照片")
                    }
                }
            }
        }
    }
}
