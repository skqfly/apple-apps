import SwiftUI

@MainActor
struct TalksScreen: View {
    @State private var store: TalksStore
    @State private var showingComposer = false
    let pending: PendingChangesStore
    let canPublish: Bool

    init(repository: GitHubRepository, pending: PendingChangesStore, canPublish: Bool) {
        _store = State(initialValue: TalksStore(repository: repository))
        self.pending = pending
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
                        TalkCard(post: post, pending: pending, canPublish: canPublish)
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
            NewTalkSheet(pending: pending) {
                Task { await store.refresh() }
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
        .onChange(of: pending.committedRevision) {
            Task { await store.refresh() }
        }
    }
}

private struct TalkCard: View {
    let post: TalkPost
    let pending: PendingChangesStore
    let canPublish: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(post.date, format: .dateTime.year().month().day())
                .font(.caption).foregroundStyle(.secondary)
            MarkdownBlocks(post.description)
            if !post.images.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(Array(post.images.enumerated()), id: \.offset) { entry in
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
                            .accessibilityHint("查看原图")
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canPublish {
                Button("下架", systemImage: "arrow.down.circle") {
                    pending.stageUnpublishTalk(talkID: post.id)
                }
                .tint(.orange)
                Button("删除", systemImage: "trash", role: .destructive) {
                    pending.stageDeleteTalk(talkID: post.id, imageSources: post.images.map(\.src))
                }
            }
        }
    }
}
