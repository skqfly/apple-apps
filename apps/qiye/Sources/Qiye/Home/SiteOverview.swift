import Foundation
import Observation

struct SiteSnapshot: Decodable {
    struct Talks: Decodable {
        struct Entry: Decodable, Identifiable {
            let id: String
            let title: String
            let date: String
            let description: String
        }
        let entries: [Entry]
    }
    let talksPageContent: Talks
}

@Observable @MainActor
final class SiteOverview {
    private(set) var talks: [SiteSnapshot.Talks.Entry] = []
    private(set) var error: String?

    init() {
        if let url = Bundle.main.url(forResource: "site", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(SiteSnapshot.self, from: data) {
            talks = snapshot.talksPageContent.entries.sorted { $0.date > $1.date }
        }
    }

    func refresh() async {
        do {
            let url = URL(string: "https://raw.githubusercontent.com/skqfly/skqfly.github.io/main/src/data/site.json")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let snapshot = try JSONDecoder().decode(SiteSnapshot.self, from: data)
            talks = snapshot.talksPageContent.entries.sorted { $0.date > $1.date }
            error = nil
        } catch {
            if !Task.isCancelled { self.error = "暂时无法更新，正在显示上次收录的内容。" }
        }
    }
}
