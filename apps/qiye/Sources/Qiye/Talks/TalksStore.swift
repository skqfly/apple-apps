import Foundation
import Observation

@Observable @MainActor
final class TalksStore {
    private(set) var posts: [TalkPost] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var publishedSHA: String?
    var query = ""
    let repository: GitHubRepository
    @ObservationIgnored private var hasLoaded = false

    init(repository: GitHubRepository) {
        self.repository = repository
        if let url = Bundle.main.url(forResource: "site", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let document = try? JSONDecoder().decode(BundledTalks.self, from: data) {
            posts = document.talksPageContent.entries
        }
    }

    var filteredPosts: [TalkPost] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return posts }
        return posts.filter { $0.title.localizedStandardContains(search) || $0.description.localizedStandardContains(search) }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        let cached = await repository.cachedTalks()
        if !cached.isEmpty { posts = cached }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await repository.fetchTalks()
            error = nil
            hasLoaded = true
        } catch is CancellationError { }
        catch {
            if !Task.isCancelled {
                self.error = "\(error.localizedDescription)\(posts.isEmpty ? "" : " 正在显示上次读取的说说。")"
            }
        }
    }

    func didPublish(sha: String) async {
        publishedSHA = sha
        // Wait for a currently running refresh before reading the new commit's content.
        // Actor network work can interleave; a new refresh after completion avoids stale UI.
        while isLoading {
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
        }
        await refresh()
    }

    private struct BundledTalks: Decodable {
        struct Page: Decodable { let entries: [TalkPost] }
        let talksPageContent: Page
    }
}
