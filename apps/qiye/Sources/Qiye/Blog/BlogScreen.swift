import SwiftUI

@MainActor
struct BlogScreen: View {
    let store: BlogStore
    @State private var category: String?
    @State private var newestFirst = true
    @Namespace private var articleTransition
    @Environment(\.dynamicTypeSize) private var typeSize
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
            VStack(alignment: .leading, spacing: 18) {
                CollectionSearchField(text: Binding(get: { store.query }, set: { store.query = $0 }), prompt: "搜索文章")
                filters
                if let error = store.error { ContentStatus(message: error) { await store.refresh() } }
                if store.isLoading && store.posts.isEmpty {
                    ProgressView("正在读取文章…").frame(maxWidth: .infinity).padding(40)
                } else if posts.isEmpty {
                    ContentUnavailableView("未找到文章", systemImage: "doc.text.magnifyingglass")
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 16) {
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
            .padding(18).padding(.bottom, 12)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle("文章").navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: BlogPost.self) { post in
            BlogDetailScreen(post: post)
                .collectionZoomDestination(id: post.id, namespace: articleTransition)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton("全部", value: nil)
                ForEach(categories, id: \.self) { value in categoryButton(value, value: value) }
                Button {
                    withAnimation(reduceMotion ? nil : CollectionStyle.spring) { newestFirst.toggle() }
                    Haptics.selection()
                } label: {
                    Label(newestFirst ? "最新" : "最早", systemImage: newestFirst ? "arrow.down" : "arrow.up")
                        .font(.caption.weight(.medium)).padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Color.appSurface, in: Capsule())
                }
                .buttonStyle(CollectionPressStyle())
            }
        }
    }

    private func categoryButton(_ title: String, value: String?) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : CollectionStyle.spring) { category = value }
            Haptics.selection()
        } label: {
            Text(title).font(.caption.weight(.semibold))
                .padding(.horizontal, 15).padding(.vertical, 10)
                .foregroundStyle(category == value ? Color.appBackground : Color.primary)
                .background(category == value ? Color.primary : Color.appSurface, in: Capsule())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityAddTraits(category == value ? [.isSelected] : [])
    }
}

struct ArticleCollectionCard: View {
    let post: BlogPost

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.primary.opacity(0.035)
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "doc.text").font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(post.title).font(.system(.title3, design: .serif).weight(.medium))
                        .lineLimit(4).minimumScaleFactor(0.85)
                }
                .padding(18)
                if let url = post.imageURL {
                    GeometryReader { geometry in
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            }
                        }
                    }
                }
            }
            .frame(height: 202).clipped()
            VStack(alignment: .leading, spacing: 7) {
                Text(post.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .frame(minHeight: 40, alignment: .topLeading)
                HStack(spacing: 4) {
                    Text(post.category ?? "随笔").lineLimit(1)
                    Spacer(minLength: 2)
                    Text(post.date, format: .dateTime.month().day())
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .collectionSurface(radius: 16).clipShape(.rect(cornerRadius: 16))
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开全文")
    }
}
