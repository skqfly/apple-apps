import Foundation
import Observation

@Observable @MainActor
final class BlogStore {
    private(set) var posts: [BlogPost] = []
    private(set) var isLoading = false
    private(set) var error: String?
    var query = ""
    private let repository: GitHubRepository
    @ObservationIgnored private var hasLoaded = false

    init(repository: GitHubRepository) {
        self.repository = repository
        let bundle = Bundle.main
        if let index = bundle.url(forResource: "blog-index", withExtension: "json", subdirectory: "BlogSnapshot")
            ?? bundle.url(forResource: "blog-index", withExtension: "json"),
           let data = try? Data(contentsOf: index),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            posts = paths.compactMap { path -> BlogPost? in
                let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let ext = URL(fileURLWithPath: path).pathExtension
                guard !name.hasPrefix("_"),
                      let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "BlogSnapshot")
                        ?? bundle.url(forResource: name, withExtension: ext),
                      let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let post = BlogPost.parse(markdown, path: path)
                guard post.metadata["draft"]?.lowercased() != "true",
                      post.metadata["published"]?.lowercased() != "false" else { return nil }
                return post
            }.sorted { $0.date == $1.date ? $0.path < $1.path : $0.date > $1.date }
        }
    }

    var filteredPosts: [BlogPost] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return posts }
        return posts.filter {
            $0.title.localizedStandardContains(search) || $0.description.localizedStandardContains(search) ||
            ($0.category?.localizedStandardContains(search) ?? false) || $0.body.localizedStandardContains(search)
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        let cached = await repository.cachedBlogPosts()
        if !cached.isEmpty { posts = cached }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await repository.fetchBlogPosts()
            posts = fetched
            error = nil
            hasLoaded = true
        } catch is CancellationError { }
        catch {
            if !Task.isCancelled {
                self.error = "\(error.localizedDescription)\(posts.isEmpty ? "" : " 正在显示上次读取的文章。")"
            }
        }
    }
}
