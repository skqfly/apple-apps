import SwiftUI

@MainActor
struct TalksScreen: View {
    @State private var store: TalksStore
    @State private var showingComposer = false
    let canPublish: Bool

    init(repository: GitHubRepository, canPublish: Bool) {
        _store = State(initialValue: TalksStore(repository: repository))
        self.canPublish = canPublish
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if !canPublish {
                    Label("连接 GitHub 后可以发布新的说说", systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let sha = store.publishedSHA {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("已提交到 GitHub", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Color.appAccent)
                        Text("提交 \(String(sha.prefix(7))) · 网站将在部署完成后更新。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
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
                    ForEach(store.filteredPosts) { post in TalkCard(post: post) }
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
            NewTalkSheet(repository: store.repository) { sha in
                await store.didPublish(sha: sha)
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
    }
}

private struct TalkCard: View {
    let post: TalkPost

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(post.date, format: .dateTime.year().month().day())
                .font(.caption).foregroundStyle(.secondary)
            Text(post.title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            MarkdownBlocks(post.description)
            if !post.images.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    // Some existing entries reuse a source; offset preserves each occurrence.
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
    }
}
