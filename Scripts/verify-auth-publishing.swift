import Foundation

// Compile with GitHubRepository, GitHubError, ContentDate, GitHubCredential and
// the BlogPost, TalkPost, WebsitePhoto models. Uses mock credentials only.
private final class MockGitHubProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (URLRequest) async throws -> (Int, Data) = { _ in
        throw URLError(.badServerResponse)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task {
            do {
                let (status, data) = try await Self.handler(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                    httpVersion: "HTTP/1.1", headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}
}

private func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}
private func body(_ request: URLRequest) throws -> [String: Any] {
    let data: Data
    if let bytes = request.httpBody { data = bytes }
    else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        data = bytes
    } else { data = Data() }
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(message: message) }
}
private struct Failure: Error { let message: String }

@main
struct VerifyAuthPublishing {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockGitHubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        // A token update while the first response is in flight must stop all
        // subsequent publishing requests, including writes under a new token.
        let stale = GitHubRepository(token: "mock-old", session: session)
        var staleRequests = 0
        MockGitHubProtocol.handler = { request in
            staleRequests += 1
            try require(request.value(forHTTPHeaderField: "Authorization") == "Bearer mock-old", "wrong initial token")
            await stale.updateToken("mock-new")
            return (200, try json(["object": ["sha": "head-a"]]))
        }
        do {
            _ = try await stale.addTalk(title: "title", content: "body")
            throw Failure(message: "stale publish unexpectedly succeeded")
        } catch GitHubError.signInRequired {}
        try require(staleRequests == 1, "stale publish sent another request")

        // A branch conflict must rebuild the manifest from the new head and use
        // a non-forced ref update. The first generated tree must not be reused.
        let repository = GitHubRepository(token: "mock-token", session: session)
        var attempt = 0
        var seenManifestRefs: [String] = []
        var manifestCounts: [Int] = []
        var parents: [String] = []
        MockGitHubProtocol.handler = { request in
            let path = request.url!.path
            switch (request.httpMethod ?? "GET", path) {
            case ("GET", let p) where p.hasSuffix("/git/ref/heads/main"):
                return (200, try json(["object": ["sha": attempt == 0 ? "head-a" : "head-b"]]))
            case ("GET", let p) where p.contains("/git/commits/"):
                return (200, try json(["sha": "parent", "tree": ["sha": "tree-\(attempt)"]]))
            case ("GET", let p) where p.contains("/contents/src/data/site.json"):
                let ref = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
                seenManifestRefs.append(ref)
                let entries: [[String: Any]] = ref == "head-a" ? [] : [["id": "concurrent", "title": "other", "date": "2026-01-01", "description": "body", "images": []]]
                let content = try json(["talksPageContent": ["entries": entries]])
                return (200, try json(["encoding": "base64", "content": content.base64EncodedString(), "sha": "manifest"]))
            case ("POST", let p) where p.hasSuffix("/git/blobs"):
                let payload = try body(request)
                let bytes = Data(base64Encoded: payload["content"] as! String)!
                let root = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
                let page = root["talksPageContent"] as! [String: Any]
                manifestCounts.append((page["entries"] as! [[String: Any]]).count)
                return (201, try json(["sha": "blob-\(attempt)"]))
            case ("POST", let p) where p.hasSuffix("/git/trees"):
                return (201, try json(["sha": "new-tree-\(attempt)"]))
            case ("POST", let p) where p.hasSuffix("/git/commits"):
                parents.append((try body(request))["parents"] as! [String] == ["head-a"] ? "head-a" : "head-b")
                return (201, try json(["sha": "commit-\(attempt)"]))
            case ("PATCH", let p) where p.hasSuffix("/git/refs/heads/main"):
                let patch = try body(request)
                try require(patch["force"] as? Bool == false, "forced ref update")
                if attempt == 0 { attempt = 1; return (422, Data()) }
                return (200, try json(["object": ["sha": "commit-1"]]))
            default: throw Failure(message: "unexpected request: \(path)")
            }
        }
        let sha = try await repository.addTalk(title: "title", content: "body")
        try require(sha == "commit-1", "wrong returned commit")
        try require(seenManifestRefs == ["head-a", "head-b"], "manifest was not reloaded")
        try require(manifestCounts == [1, 2], "concurrent talk was lost")
        try require(parents == ["head-a", "head-b"], "wrong commit parents")

        // Even authenticated reading should not consume GitHub API quota when
        // the raw public index and its content are available.
        var apiReads = 0
        MockGitHubProtocol.handler = { request in
            if request.url!.host == "api.github.com" { apiReads += 1; return (429, Data()) }
            try require(request.value(forHTTPHeaderField: "Authorization") == nil, "credential leaked to raw host")
            if request.url!.path.hasSuffix("posts.json") {
                return (200, try json(["src/content/posts/a.md", "src/content/posts/a.md"]))
            }
            return (200, Data("---\ntitle: Article\ndate: 2026-01-01\n---\nBody".utf8))
        }
        let posts = try await repository.fetchBlogPosts()
        try require(posts.count == 1 && apiReads == 0, "public index failed or duplicated entries")

        let project: [String: Any] = [
            "title": "Old", "description": "Old summary", "url": "https://example.com/project",
            "image": "/projects/a.png", "tags": ["Web"], "categories": ["Tools"], "futureField": true
        ]
        let projectsPage: [String: Any] = ["projects": [project], "subtitle": "Keep subtitle"]
        let site = try json([
            "projectsPageContent": projectsPage,
            "friendsPageContent": ["friends": [[String: Any]]()],
            "talksPageContent": ["entries": [["id": "keep-talk"]]]
        ] as [String: Any])
        let original = try JSONDecoder().decode(SiteDirectoryEntry.self, from: json(project))
        try require(original.imageURL?.absoluteString == "https://mmddskq.top/projects/a.png",
                    "relative project artwork must resolve on the website")
        let projectDraft = SiteDirectoryEntry(title: "New", description: "New summary", url: original.url,
            image: original.image, tags: original.tags, categories: original.categories, domain: nil)
        let update = try projectDraft.validated(for: .projects, replacing: original)
        let updated = try SiteDirectoryDocument.applying(update, kind: .projects, replacing: original, to: site)
        let updatedPage = updated["projectsPageContent"] as? [String: Any]
        let updatedProject = (updatedPage?["projects"] as? [[String: Any]])?.first
        try require(updatedProject?["title"] as? String == "New", "project edit not applied")
        try require(updatedProject?["futureField"] as? Bool == true && updatedPage?["subtitle"] as? String == "Keep subtitle",
                    "editing must preserve unknown fields and page metadata")
        try require(updatedProject?["categories"] as? [String] == ["Tools"], "project categories were lost")

        let friendDraft = SiteDirectoryEntry(title: "Friend", description: "", url: "https://friend.example/notes/",
            image: nil, tags: nil, categories: nil, domain: nil)
        let friend = try friendDraft.validated(for: .friends, replacing: nil)
        try require(friend.image == "https://friend.example/favicon.ico" && friend.domain == "friend.example",
                    "friend domain and fallback icon must use the destination origin")
        let added = try SiteDirectoryDocument.applying(friend, kind: .friends, replacing: nil, to: json(updated))
        let decoded = try JSONDecoder().decode(SiteDirectoryDocument.self, from: json(added))
        try require(decoded.friendsPageContent.friends == [friend] && decoded.projectsPageContent.projects == [update],
                    "adding a friend altered the project collection")
        try require((added["talksPageContent"] as? [String: Any])?["entries"] != nil,
                    "directory edit altered unrelated website content")

        do {
            _ = try SiteDirectoryDocument.applying(update, kind: .projects, replacing: original, to: json(added))
            throw Failure(message: "stale directory edit overwrote a concurrent change")
        } catch GitHubError.invalidContent(_) {}
        do {
            _ = try SiteDirectoryDocument.applying(friend, kind: .friends, replacing: nil, to: json(added))
            throw Failure(message: "duplicate friend link was accepted")
        } catch GitHubError.invalidContent(_) {}

        // Persisted pre-refresh-expiry credentials remain decodable.
        let previous = Data("{\"accessToken\":\"mock\",\"expiresAt\":0}".utf8)
        let credential = try JSONDecoder().decode(GitHubCredential.self, from: previous)
        try require(credential.refreshExpiresAt == nil && credential.needsRefresh, "legacy credential compatibility")
        print("Auth/publishing checks passed: stale credential, conflict rebuild, public quota fallback, credential migration, directory edits")
    }
}
