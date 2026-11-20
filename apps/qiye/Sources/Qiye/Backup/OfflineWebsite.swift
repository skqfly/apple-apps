import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One completed website snapshot. Source paths and file bytes match the website repository.
struct OfflineWebsite: Sendable {
    static let backupFolderName = "Website"
    static let photoIndex = "src/data/photo-library.json"
    static let siteIndex = "src/data/site.json"
    private static let manifestName = "snapshot.json"
    private static let pointerName = "current"
    private static let activationLock = NSLock()
    static var storage: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineWebsite", isDirectory: true)
    }

    let directory: URL
    let manifest: Manifest

    struct Manifest: Codable, Sendable {
        let commit: String
        let files: [String: String]
    }

    enum Install {
        case update(previous: URL?)
        case restore
    }

    private struct Pointer: Codable {
        let active: UUID
        let previous: UUID?
    }

    init(directory: URL) throws {
        self.directory = directory
        manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent(Self.manifestName)))
        guard manifest.files.keys.allSatisfy(Self.isManagedPath),
              manifest.files[Self.siteIndex] != nil, manifest.files[Self.photoIndex] != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    static func current(in storage: URL = Self.storage) -> Self? {
        guard let pointer = readPointer(in: storage) else { return nil }
        return try? Self(directory: storage.appendingPathComponent(pointer.active.uuidString, isDirectory: true))
    }

    private static func readPointer(in storage: URL) -> Pointer? {
        guard let data = try? Data(contentsOf: storage.appendingPathComponent(pointerName)) else { return nil }
        return try? JSONDecoder().decode(Pointer.self, from: data)
    }

    static func withCurrent<T>(_ body: (Self?) throws -> T) rethrows -> T {
        try activationLock.withLock { try body(current()) }
    }

    static func validatedComponents(_ path: String) -> [String]? {
        let parts = path.components(separatedBy: "/")
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") &&
            !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else { return nil }
        return parts
    }

    static func isPostPath(_ path: String) -> Bool {
        path.hasPrefix("src/content/posts/") &&
            ["md", "mdx"].contains((path as NSString).pathExtension.lowercased())
    }

    static func isManagedPath(_ path: String) -> Bool {
        guard validatedComponents(path) != nil else { return false }
        if path == photoIndex || path == siteIndex || path == "src/content/posts.json" || isPostPath(path) {
            return true
        }
        return (path.hasPrefix("public/") || path.hasPrefix("src/assets/")) &&
            ["jpg", "jpeg", "png", "webp", "heic", "gif", "svg", "avif", "ico"].contains((path as NSString).pathExtension.lowercased())
    }

    func file(_ path: String) -> URL? {
        guard manifest.files[path] != nil else { return nil }
        let url = directory.appending(path: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func data(_ path: String) throws -> Data {
        guard let url = file(path) else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }

    func blogPosts() throws -> [BlogPost] {
        try manifest.files.keys.filter(Self.isPostPath).compactMap { path -> BlogPost? in
            guard !(path as NSString).lastPathComponent.hasPrefix("_") else { return nil }
            let markdown = try data(path)
            guard let text = String(data: markdown, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let post = BlogPost.parse(text, path: path)
            guard post.metadata["draft"]?.lowercased() != "true",
                  post.metadata["published"]?.lowercased() != "false" else { return nil }
            return post
        }.sorted { $0.date == $1.date ? $0.path < $1.path : $0.date > $1.date }
    }

    func talks() throws -> [TalkPost] {
        struct Document: Decodable {
            struct Page: Decodable { let entries: [TalkPost] }
            let talksPageContent: Page
        }
        return try JSONDecoder().decode(Document.self, from: data(Self.siteIndex)).talksPageContent.entries
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }

    func validateFiles() throws {
        guard manifest.files.keys.allSatisfy({ file($0) != nil }) else { throw CocoaError(.fileNoSuchFile) }
        _ = try WebsitePhoto.decode(data(Self.photoIndex), relativeTo: GitHubRepository.websiteURL)
        _ = try JSONDecoder().decode(SiteDirectoryDocument.self, from: data(Self.siteIndex))
        _ = try blogPosts()
        _ = try talks()
    }

    func imageURL(for url: URL) -> URL? {
        WebsiteMedia.storedPaths(for: url).lazy.compactMap { self.file($0) }.first
    }

    static func createStagingDirectory(in storage: URL) throws -> URL {
        let directory = storage.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func activate(_ directory: URL, in storage: URL, operation: Install) throws -> Self {
        try activationLock.withLock {
            let snapshot = try Self(directory: directory)
            guard let id = UUID(uuidString: directory.lastPathComponent) else { throw CocoaError(.fileReadCorruptFile) }
            let old = readPointer(in: storage)
            if case let .update(previous) = operation, current(in: storage)?.directory != previous {
                throw CancellationError()
            }
            let pointer = Pointer(active: id, previous: old?.active)
            try JSONEncoder().encode(pointer).write(to: storage.appendingPathComponent(pointerName), options: .atomic)
            // Keep the previous snapshot for a view that still has an image open from it.
            if let obsolete = old?.previous {
                try? FileManager.default.removeItem(at: storage.appendingPathComponent(obsolete.uuidString))
            }
            return snapshot
        }
    }

    static func writeManifest(_ manifest: Manifest, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent(manifestName), options: .atomic)
    }

    func writeTalkMarkdown(_ talks: [TalkPost]) throws {
        let folder = directory.appendingPathComponent("Talks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, talk) in talks.enumerated() {
            let title = talk.title.isEmpty ? "说说" : talk.title
            var markdown = "# \(title)\n\n\(ContentDate.string(talk.date))\n\n\(talk.content)\n"
            for image in talk.images {
                guard let original = image.originalURL else { continue }
                let localPath = imageURL(for: original).flatMap {
                    String($0.path.dropFirst(directory.path.count)).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                }
                let link = localPath.map { ".." + $0 } ?? original.absoluteString
                let alt = (image.alt ?? "图片").replacingOccurrences(of: "]", with: "\\]")
                markdown += "\n![\(alt)](<\(link)>)\n"
            }
            try markdown.write(to: folder.appendingPathComponent(String(format: "%03d.md", index + 1)), atomically: true, encoding: .utf8)
        }
    }
}

actor OfflineWebsiteSync {
    private struct Reference: Decodable {
        struct Object: Decodable { let sha: String }
        let object: Object
    }

    private struct Tree: Decodable {
        struct Entry: Decodable, Sendable { let path: String; let sha: String; let mode: String; let type: String }
        let tree: [Entry]
        let truncated: Bool
    }

    private let storage: URL
    private let session: URLSession
    private var isSyncing = false

    init(storage: URL = OfflineWebsite.storage, session: URLSession = .shared) {
        self.storage = storage
        self.session = session
    }

    func sync(repository: GitHubRepository) async throws -> OfflineWebsite? {
        guard !isSyncing else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        let apiPath = "repos/\(GitHubRepository.owner)/\(GitHubRepository.name)"
        let branch = GitHubRepository.branch
        let refData = try await repository.getData(path: "\(apiPath)/git/ref/heads/\(branch)")
        let commit = try JSONDecoder().decode(Reference.self, from: refData).object.sha
        guard commit.utf8.count == 40, commit.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw GitHubError.invalidResponse
        }
        let previous = OfflineWebsite.current(in: storage)
        if previous?.manifest.commit == commit { return previous }
        let treeData = try await repository.getData(path: "\(apiPath)/git/trees/\(commit)?recursive=1")
        let tree = try JSONDecoder().decode(Tree.self, from: treeData)
        guard !tree.truncated else { throw GitHubError.invalidContent("网站目录过大，暂时无法生成完整离线副本。") }
        let entries = tree.tree.filter { $0.type == "blob" && $0.mode == "100644" && OfflineWebsite.isManagedPath($0.path) }
        let staging = try OfflineWebsite.createStagingDirectory(in: storage)
        do {
            var files: [String: String] = [:]
            for offset in stride(from: 0, to: entries.count, by: 4) {
                try Task.checkCancellation()
                let batch = entries.dropFirst(offset).prefix(4)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for entry in batch {
                        files[entry.path] = entry.sha
                        group.addTask {
                            try await self.stage(entry, commit: commit, from: previous, to: staging)
                        }
                    }
                    try await group.waitForAll()
                }
            }
            try OfflineWebsite.writeManifest(.init(commit: commit, files: files), in: staging)
            let snapshot = try OfflineWebsite(directory: staging)
            try snapshot.validateFiles()
            try snapshot.writeTalkMarkdown(snapshot.talks())
            try Task.checkCancellation()
            return try OfflineWebsite.activate(staging, in: storage, operation: .update(previous: previous?.directory))
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private func stage(_ entry: Tree.Entry, commit: String, from previous: OfflineWebsite?, to directory: URL) async throws {
        let destination = directory.appending(path: entry.path)
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let previous, previous.manifest.files[entry.path] == entry.sha, let source = previous.file(entry.path) {
            try fm.copyItem(at: source, to: destination)
            return
        }
        // The website repository is public. Use an immutable raw URL with no credentials.
        let raw = URL(string: "https://raw.githubusercontent.com/\(GitHubRepository.owner)/\(GitHubRepository.name)/\(commit)")!
        let source = raw.appending(path: entry.path)
        let (temporary, response) = try await session.download(from: source)
        defer { try? fm.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw GitHubError.network }
        try fm.copyItem(at: temporary, to: destination)
    }
}
