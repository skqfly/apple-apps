import Foundation

enum WebsiteMedia {
    private static let legacyPrefix = "/trilium-media/"
    private static let currentPrefix = "/media/"
    private static let siteHosts: Set<String> = ["mmddskq.top", "skqfly.github.io"]

    static func currentURL(_ url: URL) -> URL {
        URL(string: currentSource(url.absoluteString)) ?? url
    }

    /// Migrate references from older drafts while leaving local files and third-party URLs intact.
    static func currentSource(_ source: String) -> String {
        guard var url = URLComponents(string: source),
              isSiteReference(url), url.percentEncodedPath.hasPrefix(legacyPrefix) else { return source }
        url.percentEncodedPath = currentPrefix + url.percentEncodedPath.dropFirst(legacyPrefix.count)
        return url.string ?? source
    }

    static func storedPaths(for url: URL) -> [String] {
        guard let url = URLComponents(url: currentURL(url), resolvingAgainstBaseURL: true),
              isSiteReference(url), url.host != nil, url.path.hasPrefix("/") else { return [] }
        let path = url.path
        var paths = ["public" + path]
        // Cached snapshots and older backups retain the path under which the bytes were saved.
        if path.hasPrefix(currentPrefix) {
            paths.append("public" + legacyPrefix + path.dropFirst(currentPrefix.count))
        }
        return paths
    }

    private static func isSiteReference(_ url: URLComponents) -> Bool {
        if url.scheme == nil, url.host == nil { return true }
        guard let host = url.host?.lowercased(), siteHosts.contains(host),
              url.user == nil, url.password == nil, url.port == nil else { return false }
        return url.scheme == nil || url.scheme == "https" || url.scheme == "http"
    }
}
