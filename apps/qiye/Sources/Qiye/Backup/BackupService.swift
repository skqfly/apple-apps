import Foundation

/// Coordinates a folder-based backup with the app's on-disk storage, and knows
/// how to move a finished backup folder to/from WebDAV.
struct BackupService {
    /// Top-level folders under Application Support that make up a full backup.
    static let folderNames = ["Publishing", "Photos"]

    static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Copies the managed folders into a single backup directory and writes a
    /// manifest listing every file so WebDAV can restore without a directory listing.
    func prepareBackupFolder(to folderURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let root = Self.applicationSupportURL
        var relativePaths: [String] = []
        for folder in Self.folderNames {
            let source = root.appendingPathComponent(folder)
            let destination = folderURL.appendingPathComponent(folder)
            guard fm.fileExists(atPath: source.path) else { continue }
            try copyFolder(from: source, to: destination)
            relativePaths += files(under: destination, relativeTo: folderURL)
        }
        let manifest = BackupManifest(version: 1, files: relativePaths)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: folderURL.appendingPathComponent("manifest.json"), options: .atomic)
    }

    /// Restores a backup folder into Application Support. Changes appear after relaunch.
    func restore(from folderURL: URL) throws {
        let fm = FileManager.default
        let root = Self.applicationSupportURL
        for folder in Self.folderNames {
            let source = folderURL.appendingPathComponent(folder)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = root.appendingPathComponent(folder)
            try copyFolder(from: source, to: destination)
        }
    }

    // MARK: - WebDAV

    func webDAVUpload(folderURL: URL, folderName: String, to server: WebDAVServer) async throws {
        let manifestURL = folderURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        let client = WebDAVClient(server: server)
        try await client.makeFolder(folderName)
        try await client.upload(manifestData, path: "\(folderName)/manifest.json")
        for relative in manifest.files {
            let data = try Data(contentsOf: folderURL.appendingPathComponent(relative))
            try await client.upload(data, path: "\(folderName)/\(relative)")
        }
    }

    func webDAVDownload(folderName: String, from server: WebDAVServer) async throws -> URL {
        let client = WebDAVClient(server: server)
        let manifestData = try await client.download("\(folderName)/manifest.json")
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QiyeBackups", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try manifestData.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        for relative in manifest.files {
            let data = try await client.download("\(folderName)/\(relative)")
            let destination = directory.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        return directory
    }

    // MARK: - Helpers

    private func copyFolder(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])
        for item in items {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if isDirectory {
                try copyFolder(from: item, to: target)
            } else {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    private func files(under directory: URL, relativeTo base: URL) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var result: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = url.path.replacingOccurrences(of: base.path + "/", with: "")
            result.append(relative)
        }
        return result.sorted()
    }
}

struct BackupManifest: Codable {
    let version: Int
    let files: [String]
}

struct WebDAVServer: Codable, Equatable {
    var baseURL: URL
    var username: String
    var password: String
}

/// A minimal WebDAV client: MKCOL, PUT and GET with HTTP Basic auth.
struct WebDAVClient {
    let server: WebDAVServer
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()

    func makeFolder(_ name: String) async throws {
        var request = URLRequest(url: server.baseURL.appendingPathComponent(name, isDirectory: true))
        request.httpMethod = "MKCOL"
        applyAuth(&request)
        let (_, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) || http.statusCode == 405 else {
            throw BackupError.webDAVFailed
        }
    }

    func upload(_ data: Data, path: String) async throws {
        var request = URLRequest(url: url(forPath: path))
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        try await perform(request)
    }

    func download(_ path: String) async throws -> Data {
        var request = URLRequest(url: url(forPath: path))
        request.httpMethod = "GET"
        return try await data(request)
    }

    private func url(forPath path: String) -> URL {
        path.split(separator: "/").reduce(server.baseURL) { $0.appendingPathComponent(String($1)) }
    }

    private func applyAuth(_ request: inout URLRequest) {
        let credential = "\(server.username):\(server.password)"
        if let encoded = credential.data(using: .utf8)?.base64EncodedString() {
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
    }

    private func perform(_ request: URLRequest) async throws {
        var request = request
        applyAuth(&request)
        let (_, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BackupError.webDAVFailed
        }
    }

    private func data(_ request: URLRequest) async throws -> Data {
        var request = request
        applyAuth(&request)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BackupError.webDAVFailed
        }
        return data
    }
}

enum BackupError: LocalizedError {
    case noServer
    case invalidServerURL
    case webDAVFailed

    var errorDescription: String? {
        switch self {
        case .noServer: return "请先填写 WebDAV 服务器地址、用户名和密码，或输入备份文件夹名。"
        case .invalidServerURL: return "WebDAV 地址无效，请填写完整的 https:// 地址。"
        case .webDAVFailed: return "WebDAV 请求失败，请检查地址、账号密码和网络。"
        }
    }
}
