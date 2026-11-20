import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Coordinates a folder-based backup with the app's on-disk storage, and knows
/// how to move a finished backup folder to/from WebDAV.
actor BackupService {
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
        try OfflineWebsite.withCurrent { snapshot in
            guard let snapshot else { return }
            let destination = folderURL.appendingPathComponent(OfflineWebsite.backupFolderName, isDirectory: true)
            try copyFolder(from: snapshot.directory, to: destination)
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
        let website = folderURL.appendingPathComponent(OfflineWebsite.backupFolderName, isDirectory: true)
        if fm.fileExists(atPath: website.path) {
            let staging = try OfflineWebsite.createStagingDirectory(in: OfflineWebsite.storage)
            do {
                try copyFolder(from: website, to: staging)
                let snapshot = try OfflineWebsite(directory: staging)
                try snapshot.validateFiles()
                _ = try OfflineWebsite.activate(staging, in: OfflineWebsite.storage, operation: .restore)
            } catch {
                try? fm.removeItem(at: staging)
                throw error
            }
        }
        for folder in Self.folderNames {
            let source = folderURL.appendingPathComponent(folder)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = root.appendingPathComponent(folder)
            try copyFolder(from: source, to: destination)
        }
    }

    // MARK: - WebDAV

    func webDAVUpload(folderURL: URL, folderName: String, to server: WebDAVServer) async throws {
        try validateFolderName(folderName)
        let manifestURL = folderURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        try validateManifest(manifest)
        let client = WebDAVClient(server: server)
        try await client.makeFolder(folderName)
        var folders = Set([folderName])
        for relative in manifest.files {
            var parent = folderName
            for component in relative.split(separator: "/").dropLast() {
                parent += "/\(component)"
                if folders.insert(parent).inserted { try await client.makeFolder(parent) }
            }
            try await client.upload(file: folderURL.appending(path: relative), path: "\(folderName)/\(relative)")
        }
        try await client.upload(manifestData, path: "\(folderName)/manifest.json")
    }

    func webDAVDownload(folderName: String, from server: WebDAVServer) async throws -> URL {
        try validateFolderName(folderName)
        let client = WebDAVClient(server: server)
        let manifestData = try await client.download("\(folderName)/manifest.json")
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        try validateManifest(manifest)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QiyeBackups", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            for relative in manifest.files {
                let destination = directory.appending(path: relative)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await client.download("\(folderName)/\(relative)", to: destination)
            }
            try manifestData.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    // MARK: - Helpers

    private func validateFolderName(_ name: String) throws {
        guard OfflineWebsite.validatedComponents(name)?.count == 1 else { throw BackupError.invalidManifest }
    }

    private func validateManifest(_ manifest: BackupManifest) throws {
        let roots = Self.folderNames + [OfflineWebsite.backupFolderName]
        guard manifest.version == 1, Set(manifest.files).count == manifest.files.count,
              manifest.files.allSatisfy({ path in
                  guard let parts = OfflineWebsite.validatedComponents(path), parts.count >= 2 else { return false }
                  return roots.contains(parts[0])
              }) else { throw BackupError.invalidManifest }
    }

    private func copyFolder(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let sourceType = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard sourceType.isDirectory == true, sourceType.isSymbolicLink != true else { throw BackupError.invalidManifest }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
        for item in items {
            let kind = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard kind.isSymbolicLink != true else { throw BackupError.invalidManifest }
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if kind.isDirectory == true {
                try copyFolder(from: item, to: target)
            } else if kind.isRegularFile == true {
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
        let url = url(forPath: name)
        var request = URLRequest(url: url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent, isDirectory: true))
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

    func upload(file: URL, path: String) async throws {
        var request = URLRequest(url: url(forPath: path))
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        let (_, response) = try await session.upload(for: request, fromFile: file)
        try checkResponse(response)
    }

    func download(_ path: String, to destination: URL) async throws {
        var request = URLRequest(url: url(forPath: path))
        applyAuth(&request)
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try checkResponse(response)
        try FileManager.default.copyItem(at: temporary, to: destination)
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
        try checkResponse(response)
    }

    private func data(_ request: URLRequest) async throws -> Data {
        var request = request
        applyAuth(&request)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return data
    }

    private func checkResponse(_ response: URLResponse) throws {
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BackupError.webDAVFailed
        }
    }
}

enum BackupError: LocalizedError {
    case noServer
    case invalidServerURL
    case webDAVFailed
    case invalidManifest

    var errorDescription: String? {
        switch self {
        case .noServer: return "请先填写 WebDAV 服务器地址、用户名和密码，或输入备份文件夹名。"
        case .invalidServerURL: return "WebDAV 地址无效，请填写完整的 https:// 地址。"
        case .webDAVFailed: return "WebDAV 请求失败，请检查地址、账号密码和网络。"
        case .invalidManifest: return "备份清单、文件路径或文件夹名称无效。"
        }
    }
}
