import Foundation

enum DirectoryKind: String, Hashable, Identifiable, Sendable {
    case projects, friends

    var id: Self { self }
    var title: String { self == .projects ? "项目" : "友链" }
    var symbol: String { self == .projects ? "rectangle.3.group" : "person.2" }
    var pageKey: String { self == .projects ? "projectsPageContent" : "friendsPageContent" }
}

struct SiteDirectoryEntry: Decodable, Equatable, Identifiable, Sendable {
    var id: String { url }
    let title: String
    let description: String
    let url: String
    let image: String?
    let tags: [String]?
    let categories: [String]?
    let domain: String?

    var destination: URL? { Self.webURL(url) }
    var imageURL: URL? {
        image.flatMap { Self.webURL($0, relativeTo: GitHubRepository.websiteURL) }.map(WebsiteMedia.currentURL)
    }

    private static func webURL(_ value: String, relativeTo base: URL? = nil) -> URL? {
        guard !value.isEmpty, let url = URL(string: value, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }

    func validated(for kind: DirectoryKind, replacing original: Self?) throws -> Self {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = image?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, let destination = Self.webURL(url), let host = destination.host else {
            throw GitHubError.invalidContent("请填写名称和有效的 http:// 或 https:// 链接。")
        }
        if !image.isEmpty, Self.webURL(image, relativeTo: GitHubRepository.websiteURL) == nil {
            throw GitHubError.invalidContent("图片地址须为网址或站内路径。")
        }

        let favicon = URL(string: "/favicon.ico", relativeTo: destination)?.absoluteURL.absoluteString
        let fallbackImage = kind == .friends ? favicon : "/favicon.svg"
        return Self(title: title, description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    url: url, image: image.isEmpty ? fallbackImage : WebsiteMedia.currentSource(image),
                    tags: kind == .projects ? tags ?? [] : nil,
                    categories: kind == .projects ? categories ?? [] : nil,
                    domain: kind == .friends ? (original?.url == url ? original?.domain ?? host : host) : nil)
    }
}

struct SiteDirectoryDocument: Decodable {
    struct Projects: Decodable { let projects: [SiteDirectoryEntry] }
    struct Friends: Decodable { let friends: [SiteDirectoryEntry] }
    let projectsPageContent: Projects
    let friendsPageContent: Friends
    static let path = "src/data/site.json"

    static func applying(_ entry: SiteDirectoryEntry, kind: DirectoryKind,
                         replacing original: SiteDirectoryEntry?, to data: Data) throws -> [String: Any] {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var page = root[kind.pageKey] as? [String: Any],
              var entries = page[kind.rawValue] as? [[String: Any]] else {
            throw GitHubError.invalidContent("网站目录结构已变化，本次未修改文件。")
        }

        let matches = entries.indices.filter { index in
            entries[index]["url"] as? String == (original?.url ?? entry.url)
        }
        var indexToReplace: Int?
        if let original {
            guard matches.count == 1, let index = matches.first,
                  let bytes = try? JSONSerialization.data(withJSONObject: entries[index]),
                  let current = try? JSONDecoder().decode(SiteDirectoryEntry.self, from: bytes),
                  current == original else {
                throw GitHubError.invalidContent("这条记录已在网站上修改或移除。请刷新目录后重新编辑。")
            }
            indexToReplace = index
        }
        guard !entries.indices.contains(where: { $0 != indexToReplace && entries[$0]["url"] as? String == entry.url }) else {
            throw GitHubError.invalidContent("该目录已有相同链接。")
        }

        var updated = indexToReplace.map { entries[$0] } ?? [:]
        updated["title"] = entry.title
        updated["description"] = entry.description
        updated["url"] = entry.url
        updated["image"] = entry.image
        if kind == .projects {
            updated["tags"] = entry.tags ?? []
            updated["categories"] = entry.categories ?? []
        } else {
            updated["domain"] = entry.domain
        }

        if let indexToReplace { entries[indexToReplace] = updated }
        else { entries.insert(updated, at: 0) }
        page[kind.rawValue] = entries
        root[kind.pageKey] = page
        return root
    }
}
