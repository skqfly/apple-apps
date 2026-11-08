import Foundation

/// Coordinates the archive's contents with the app's on-disk storage, and knows
/// how to move a finished archive to/from WebDAV.
struct BackupService {
    /// Top-level folders under Application Support that make up a full backup.
    static let folderNames = ["Publishing", "Photos"]

    static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Collects every file under the managed folders and writes one archive.
    func makeArchive(to destination: URL) throws {
        let root = Self.applicationSupportURL
        var files: [(path: String, url: URL)] = []
        for folder in Self.folderNames {
            collect(folderURL: root.appendingPathComponent(folder), into: &files)
        }
        try BackupArchive.write(files: files, to: destination)
    }

    /// Restores an archive into Application Support. Changes appear after relaunch.
    func restore(from archive: URL) throws {
        try BackupArchive.extract(archive, to: Self.applicationSupportURL)
    }

    // MARK: - WebDAV

    func webDAVUpload(_ archive: URL, to server: WebDAVServer) async throws {
        let data = try Data(contentsOf: archive)
        let filename = archive.lastPathComponent
        try await WebDAVClient(server: server).upload(data, filename: filename)
    }

    func webDAVDownload(_ filename: String, from server: WebDAVServer) async throws -> Data {
        try await WebDAVClient(server: server).download(filename: filename)
    }

    // MARK: - Helpers

    private func collect(folderURL: URL, into files: inout [(path: String, url: URL)]) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return }
        let root = Self.applicationSupportURL
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append((path: relative, url: url))
        }
    }
}

struct WebDAVServer: Codable, Equatable {
    var baseURL: URL
    var username: String
    var password: String
}

/// A minimal WebDAV client: PUT for upload and GET for download, with HTTP Basic auth.
struct WebDAVClient {
    let server: WebDAVServer
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    func upload(_ data: Data, filename: String) async throws {
        var request = URLRequest(url: endpoint(filename))
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        try await perform(request)
    }

    func download(_ filename: String) async throws -> Data {
        var request = URLRequest(url: endpoint(filename))
        request.httpMethod = "GET"
        return try await data(request)
    }

    private func endpoint(_ filename: String) -> URL {
        server.baseURL.appendingPathComponent(filename)
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
        case .noServer: return "请先填写 WebDAV 服务器地址、用户名和密码。"
        case .invalidServerURL: return "WebDAV 地址无效，请填写完整的 https:// 地址。"
        case .webDAVFailed: return "WebDAV 请求失败，请检查地址、账号密码和网络。"
        }
    }
}
