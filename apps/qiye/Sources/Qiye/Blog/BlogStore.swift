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

    init(repository: GitHubRepository) { self.repository = repository }

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
        if posts.isEmpty { posts = await repository.cachedBlogPosts() }
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
