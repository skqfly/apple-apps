import Foundation

/// All writes target one non-forced commit on main. Credentials remain actor isolated.
actor GitHubRepository {
    static let owner = "skqfly"
    static let name = "skqfly.github.io"
    static let branch = "main"
    static let websiteURL = URL(string: "https://mmddskq.top")!

    private var token: String?
    private let session: URLSession
    private let repositoryPath = "repos/skqfly/skqfly.github.io"
    private var blogCache: [BlogPost] = []
    private var talksCache: [TalkPost] = []

    init(token: String? = nil, session: URLSession = .shared) {
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func updateToken(_ token: String?) {
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// GitHub API endpoint, for example `user` or `repos/.../actions/runs?per_page=10`.
    /// Only api.github.com is accepted, so a token cannot be forwarded to another host.
    func getData(path: String) async throws -> Data {
        try await request(path: path)
    }

    /// Query GitHub GraphQL using the same actor-isolated credential.
    func graphQL(query: String, variables: [String: String] = [:]) async throws -> Data {
        try await request(path: "graphql", method: "POST", body: ["query": query, "variables": variables])
    }

    func getRepositoryFile(path: String) async throws -> Data {
        try await repositoryFile(path: path, ref: Self.branch)
    }

    func cachedBlogPosts() -> [BlogPost] { blogCache }
    func cachedTalks() -> [TalkPost] { talksCache }

    func fetchBlogPosts() async throws -> [BlogPost] {
        let head: Reference = try await decode(path: "\(repositoryPath)/git/ref/heads/\(Self.branch)")
        let tree: GitTree = try await decode(path: "\(repositoryPath)/git/trees/\(head.object.sha)?recursive=1")
        guard !tree.truncated else {
            throw GitHubError.invalidContent("博客目录过大，暂时无法完整读取。")
        }
        let files = tree.tree.filter {
            $0.type == "blob" && $0.path.hasPrefix("src/content/posts/") &&
            ["md", "mdx"].contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased())
        }
        var posts: [BlogPost] = []
        // Read immutable blobs from the captured tree, avoiding a mixed snapshot if main moves.
        // Four requests at a time keeps large blogs responsive without overwhelming GitHub.
        for offset in stride(from: 0, to: files.count, by: 4) {
            let batch = Array(files[offset..<min(offset + 4, files.count)])
            let result = try await withThrowingTaskGroup(of: BlogPost.self) { group in
                for file in batch {
                    group.addTask {
                        let data = try await self.blob(sha: file.sha)
                        guard let markdown = String(data: data, encoding: .utf8) else {
                            throw GitHubError.invalidContent("文章不是有效的 UTF-8 文本。")
                        }
                        return BlogPost.parse(markdown, path: file.path)
                    }
                }
                var result: [BlogPost] = []
                for try await post in group { result.append(post) }
                return result
            }
            posts.append(contentsOf: result)
        }
        posts.sort { $0.date == $1.date ? $0.path < $1.path : $0.date > $1.date }
        blogCache = posts
        return posts
    }

    func fetchTalks() async throws -> [TalkPost] {
        let data = try await getRepositoryFile(path: "src/data/site.json")
        let snapshot: TalksDocument
        do { snapshot = try JSONDecoder().decode(TalksDocument.self, from: data) }
        catch { throw GitHubError.invalidContent("网站说说资料格式已变化，暂时无法读取。") }
        let posts = snapshot.talksPageContent.entries.sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
        }
        talksCache = posts
        return posts
    }

    func fetchPhotos() async throws -> [WebsitePhoto] {
        let data = try await getRepositoryFile(path: "src/data/photo-library.json")
        do { return try WebsitePhoto.decode(data, relativeTo: Self.websiteURL) }
        catch { throw GitHubError.invalidContent("网站照片资料格式已变化，暂时无法读取。") }
    }

    private func repositoryFile(path: String, ref: String) async throws -> Data {
        let encodedPath = path.split(separator: "/").map { Self.escape(String($0)) }.joined(separator: "/")
        let content: EncodedFile = try await decode(
            path: "\(repositoryPath)/contents/\(encodedPath)?ref=\(Self.escape(ref))"
        )
        guard content.encoding == "base64", let value = content.content,
              let data = Data(base64Encoded: value, options: .ignoreUnknownCharacters) else {
            // GitHub omits Contents API bodies above 1 MB; fetch its immutable blob instead.
            if let sha = content.sha { return try await blob(sha: sha) }
            throw GitHubError.invalidResponse
        }
        return data
    }

    private func blob(sha: String) async throws -> Data {
        let content: EncodedFile = try await decode(path: "\(repositoryPath)/git/blobs/\(sha)")
        guard content.encoding == "base64", let value = content.content,
              let data = Data(base64Encoded: value, options: .ignoreUnknownCharacters) else {
            throw GitHubError.invalidResponse
        }
        return data
    }

    private func decode<T: Decodable>(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let data = try await request(path: path, method: method, body: body)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GitHubError.invalidResponse }
    }

    private func request(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !relative.hasPrefix("/"), !relative.contains("://"),
              let base = URL(string: "https://api.github.com/"),
              let url = URL(string: relative, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host == "api.github.com", url.user == nil, url.password == nil else {
            throw GitHubError.invalidResponse
        }
        if method != "GET", token?.isEmpty != false { throw GitHubError.signInRequired }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 45
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Qiye-iOS", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw GitHubError.http(http.statusCode, rateLimited: http.statusCode == 429 ||
                    (http.statusCode == 403 && (http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" ||
                        http.value(forHTTPHeaderField: "Retry-After") != nil)))
            }
            return data
        } catch let error as GitHubError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw GitHubError.network }
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }

    private struct EncodedFile: Decodable { let encoding: String; let content: String?; let sha: String? }
    private struct GitObject: Decodable { let sha: String }
    private struct Reference: Decodable { let object: GitObject }
    private struct Commit: Decodable { let sha: String; let tree: GitObject }
    private struct TreeEntry: Decodable, Sendable { let path: String; let type: String; let sha: String }
    private struct GitTree: Decodable { let tree: [TreeEntry]; let truncated: Bool }
    private struct TalksDocument: Decodable {
        struct Page: Decodable { let entries: [TalkPost] }
        let talksPageContent: Page
    }
}

extension GitHubRepository {
    @discardableResult
    func addTalk(title: String, content: String, date: Date = .now) async throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !content.isEmpty else {
            throw GitHubError.invalidContent("请填写说说标题和正文。")
        }
        guard title.count <= 200, content.count <= 50_000 else {
            throw GitHubError.invalidContent("标题最多 200 字，正文最多 50,000 字。")
        }
        let id = "qiye-\(UUID().uuidString.lowercased())"
        let dateString = ContentDate.string(date)
        let sha = try await publish(message: "Add talk from Qiye", assets: [:]) { head in
            let data = try await self.repositoryFile(path: "src/data/site.json", ref: head)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var page = root["talksPageContent"] as? [String: Any],
                  var entries = page["entries"] as? [[String: Any]] else {
                throw GitHubError.invalidContent("网站说说数据结构已变化，本次未修改文件。")
            }
            entries.insert(["id": id, "title": title, "date": dateString,
                            "description": content, "images": [] as [String]], at: 0)
            page["entries"] = entries
            root["talksPageContent"] = page
            return ["src/data/site.json": try Self.json(root)]
        }
        return sha
    }

    /// The caller supplies JPEG bytes (for example UIImage.jpegData), not HEIC/PNG bytes.
    /// `title` is stored only as accessibility alt text; it adds no visible photo caption.
    @discardableResult
    func addPhoto(data: Data, filename: String, width: Int, height: Int, title: String) async throws -> String {
        guard data.count >= 3, data.starts(with: [0xFF, 0xD8, 0xFF]), width > 0, height > 0 else {
            throw GitHubError.invalidContent("请选择有效的 JPEG 照片，且图片尺寸必须大于零。")
        }
        guard data.count <= 25 * 1024 * 1024 else {
            throw GitHubError.invalidContent("照片不能超过 25 MB，请压缩后重试。")
        }
        let id = "qiye-\(UUID().uuidString.lowercased())"
        let source = "/photos/\(id).jpg"
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let alt = trimmedTitle.isEmpty ? "照片" : String(trimmedTitle.prefix(500))
        return try await publish(message: "Add photo from Qiye", assets: ["public\(source)": data]) { head in
            let current = try await self.repositoryFile(path: "src/data/photo-library.json", ref: head)
            guard var library = try JSONSerialization.jsonObject(with: current) as? [String: Any],
                  library.values.allSatisfy({ $0 is [String: Any] }) else {
                throw GitHubError.invalidContent("网站照片清单结构已变化，本次未修改文件。")
            }
            library[id] = ["src": source, "preview": source, "previewLarge": source,
                           "width": width, "height": height, "alt": alt]
            return ["src/data/photo-library.json": try Self.json(library)]
        }
    }

    private static func json(_ value: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    private func publish(
        message: String, assets: [String: Data],
        manifest: (String) async throws -> [String: Data]
    ) async throws -> String {
        guard token?.isEmpty == false else { throw GitHubError.signInRequired }
        // Assets have stable UUID paths and immutable blobs, so they can be reused after a conflict.
        var assetSHAs: [String: String] = [:]
        for (path, data) in assets {
            let object: GitObject = try await decode(path: "\(repositoryPath)/git/blobs", method: "POST",
                body: ["content": data.base64EncodedString(), "encoding": "base64"])
            assetSHAs[path] = object.sha
        }
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let head: Reference = try await decode(path: "\(repositoryPath)/git/ref/heads/\(Self.branch)")
            let parent: Commit = try await decode(path: "\(repositoryPath)/git/commits/\(head.object.sha)")
            let files = try await manifest(head.object.sha)
            var shas = assetSHAs
            for (path, data) in files {
                let object: GitObject = try await decode(path: "\(repositoryPath)/git/blobs", method: "POST",
                    body: ["content": data.base64EncodedString(), "encoding": "base64"])
                shas[path] = object.sha
            }
            let treeEntries: [[String: Any]] = shas.keys.sorted().map {
                ["path": $0, "mode": "100644", "type": "blob", "sha": shas[$0] ?? ""]
            }
            let tree: GitObject = try await decode(path: "\(repositoryPath)/git/trees", method: "POST",
                body: ["base_tree": parent.tree.sha, "tree": treeEntries])
            let commit: GitObject = try await decode(path: "\(repositoryPath)/git/commits", method: "POST",
                body: ["message": message, "tree": tree.sha, "parents": [head.object.sha]])
            do {
                let _: Reference = try await decode(path: "\(repositoryPath)/git/refs/heads/\(Self.branch)", method: "PATCH",
                    body: ["sha": commit.sha, "force": false])
                return commit.sha
            } catch let error as GitHubError {
                switch error {
                case .http(let status, _) where status == 409 || status == 422:
                    let latest: Reference = try await decode(path: "\(repositoryPath)/git/ref/heads/\(Self.branch)")
                    guard latest.object.sha != head.object.sha else { throw error }
                    if attempt == 2 { throw GitHubError.conflict }
                    // Reload the changed manifest on the new parent; never reuse stale JSON.
                    continue
                case .network, .invalidResponse:
                    if await containsCommit(commit.sha) { return commit.sha }
                    throw GitHubError.publishUncertain
                case .http(let status, _) where status >= 500:
                    if await containsCommit(commit.sha) { return commit.sha }
                    throw GitHubError.publishUncertain
                default: throw error
                }
            } catch is CancellationError {
                // The request might have reached GitHub before the connection was cancelled.
                throw GitHubError.publishUncertain
            }
        }
        throw GitHubError.conflict
    }

    private func containsCommit(_ sha: String) async -> Bool {
        struct Comparison: Decodable { let status: String }
        guard let comparison: Comparison = try? await decode(
            path: "\(repositoryPath)/compare/\(sha)...\(Self.branch)"
        ) else { return false }
        return comparison.status == "ahead" || comparison.status == "identical"
    }
}
