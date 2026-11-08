import SwiftUI

@MainActor
struct BlogScreen: View {
    @State private var store: BlogStore
    #if DEBUG
    @State private var screenshotPost: BlogPost?
    @State private var showsScreenshotArticle = false
    @State private var openedScreenshotArticle = false
    #endif

    init(repository: GitHubRepository) {
        _store = State(initialValue: BlogStore(repository: repository))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                if let error = store.error {
                    ContentStatus(message: error) { await store.refresh() }
                }
                if store.isLoading && store.posts.isEmpty {
                    ProgressView("正在读取 GitHub 文章…")
                        .frame(maxWidth: .infinity).padding(.vertical, 60)
                } else if store.filteredPosts.isEmpty && (store.error == nil || !store.posts.isEmpty) {
                    ContentUnavailableView(
                        store.query.isEmpty ? "还没有文章" : "未找到文章",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(store.query.isEmpty ? "下拉刷新以读取网站的最新博客。" : "试试其他标题、分类或正文关键词。")
                    )
                } else {
                    ForEach(store.filteredPosts) { post in
                        NavigationLink(value: post) {
                            BlogPostRow(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle("博客")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.query, prompt: "搜索标题、分类或正文")
        .navigationDestination(for: BlogPost.self) { post in BlogDetailScreen(post: post) }
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
        #if DEBUG
        .navigationDestination(isPresented: $showsScreenshotArticle) {
            if let screenshotPost { BlogDetailScreen(post: screenshotPost) }
        }
        .task(id: store.posts.first?.id) {
            guard ProcessInfo.processInfo.arguments.contains("--article"), !openedScreenshotArticle,
                  let post = store.posts.first(where: { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
            openedScreenshotArticle = true
            screenshotPost = post
            showsScreenshotArticle = true
        }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !store.posts.isEmpty {
                Text("\(store.posts.count) 篇文章")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct BlogPostRow: View {
    let post: BlogPost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let category = post.category, !category.isEmpty {
                    Text(category).font(.caption.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.appAccent.opacity(0.10), in: Capsule())
                }
                if post.date != .distantPast {
                    Text(post.date, format: .dateTime.year().month().day())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Text(post.title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            if !post.description.isEmpty {
                Text(post.description).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(3).multilineTextAlignment(.leading).lineSpacing(3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 18, interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开全文")
    }
}
