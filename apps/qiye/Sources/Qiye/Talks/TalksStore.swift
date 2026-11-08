import Foundation
import Observation

@Observable @MainActor
final class TalksStore {
    private(set) var hasRemoteSnapshot = false
    private(set) var posts: [TalkPost] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var publishedSHA: String?
    var query = ""
    let repository: GitHubRepository
    @ObservationIgnored private var hasLoaded = false

    init(repository: GitHubRepository) {
        self.repository = repository
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-content") {
            installTimelineFixture()
            hasLoaded = true
            return
        }
        #endif
        if let url = Bundle.main.url(forResource: "site", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let document = try? JSONDecoder().decode(BundledTalks.self, from: data) {
            posts = document.talksPageContent.entries.sorted { $0.date > $1.date }
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-content") { return }
        #endif
        guard !isLoading else { return }
        hasRemoteSnapshot = false
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await repository.fetchTalks()
            hasRemoteSnapshot = true
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

    #if DEBUG
    private func installTimelineFixture() {
        let nested = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: "PhotoPreviews") ?? []
        let imageURLs = nested.isEmpty ? (Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: nil) ?? []) : nested
        let selected = Array(imageURLs.sorted { $0.path < $1.path }.prefix(9))
        guard !selected.isEmpty else { error = "未找到测试图片"; return }
        let nineFirst = ProcessInfo.processInfo.arguments.contains("--nine-first")
        let counts = nineFirst ? [9, 6] : [6, 9]
        let entries: [[String: Any]] = counts.enumerated().map { index, count in
            let images: [[String: Any]] = (0..<count).map { offset in
                let source = selected[offset % selected.count].absoluteString
                return ["src": source, "preview": source, "previewLarge": source, "width": 900, "height": 900, "alt": "验证图片 \(offset + 1)"]
            }
            return ["id": count == 6 ? "fixture-six" : "fixture-nine", "title": "", "description": count == 6 ? "六张照片，记录一天的片刻。" : "九张照片，把值得记住的瞬间留在这里。", "date": index == 0 ? "2026-11-08T04:00:00Z" : "2026-11-07T04:00:00Z", "images": images]
        }
        if let data = try? JSONSerialization.data(withJSONObject: entries), let fixture = try? JSONDecoder().decode([TalkPost].self, from: data) { posts = fixture }
    }
    #endif

    private struct BundledTalks: Decodable {
        struct Page: Decodable { let entries: [TalkPost] }
        let talksPageContent: Page
    }
}
