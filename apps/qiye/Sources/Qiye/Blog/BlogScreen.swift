import SwiftUI

@MainActor
struct BlogScreen: View {
    let store: BlogStore
    @State private var category: String?
    @State private var newestFirst = true
    @Namespace private var articleTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @State private var screenshotPost: BlogPost?
    @State private var showsScreenshotArticle = false
    @State private var openedScreenshotArticle = false
    #endif

    private var categories: [String] { Array(Set(store.posts.compactMap(\.category))).sorted() }
    private var posts: [BlogPost] {
        let filtered = store.filteredPosts.filter { category == nil || $0.category == category }
        return newestFirst ? filtered : Array(filtered.reversed())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                filters
                articleResults
            }
            .padding(.bottom, 30)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .appPageBackground()
        .appNavigationTitle("博客")
        .searchable(text: Binding(get: { store.query }, set: { store.query = $0 }),
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索博客")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排序", selection: $newestFirst) {
                        Text("最新优先").tag(true)
                        Text("最早优先").tag(false)
                    }
                } label: {
                    ToolbarActionIcon("排序", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
        .navigationDestination(for: BlogPost.self) { post in
            if reduceMotion {
                BlogDetailScreen(post: post)
            } else {
                BlogDetailScreen(post: post)
                    .collectionZoomDestination(id: post.id, namespace: articleTransition)
            }
        }
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

    private var filters: some View {
        CollectionFilterBar {
            categoryButton("全部", value: nil)
            ForEach(categories, id: \.self) { value in categoryButton(value, value: value) }
        }
    }

    private var articleResults: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = store.error { ContentStatus(message: error) { await store.refresh() } }
            if store.isLoading && store.posts.isEmpty {
                ProgressView("正在读取博客…").frame(maxWidth: .infinity).padding(40)
            } else if posts.isEmpty {
                if !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: store.query)
                } else {
                    ContentUnavailableView(
                        category == nil ? "暂无博客" : "这个分类暂无博客",
                        systemImage: "doc.text",
                        description: Text(category == nil ? "下拉刷新，查看最新文章。" : "切换分类，查看其他文章。")
                    )
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(posts) { post in
                        NavigationLink(value: post) {
                            ArticleCollectionCard(post: post)
                                .collectionZoomSource(id: post.id, namespace: articleTransition)
                        }
                        .buttonStyle(CollectionPressStyle())
                        .accessibilityIdentifier("article-\(post.id)")
                    }
                }
            }
        }
        .padding(.horizontal, AppPageLayout.horizontalInset)
    }

    private func categoryButton(_ title: String, value: String?) -> some View {
        CollectionFilterChip(title: title, isSelected: category == value) {
            category = value
        }
    }
}

struct ArticleCollectionCard: View {
    let post: BlogPost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { metadata }
                VStack(alignment: .leading, spacing: 4) { metadata }
            }
            .font(.subheadline)
            Text(post.title)
                .font(.title3.weight(.semibold))
            if !post.description.isEmpty {
                Text(post.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .collectionSurface(radius: 18)
        .contentShape(.rect(cornerRadius: 18))
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开全文")
    }

    @ViewBuilder private var metadata: some View {
        if let category = post.category, !category.isEmpty {
            Text(category).foregroundStyle(Color.appAccent)
        }
        if post.date != .distantPast {
            Text(post.date, format: .dateTime.year().month().day())
                .foregroundStyle(.secondary)
        }
    }
}
