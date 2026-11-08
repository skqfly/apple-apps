import Foundation

/// A tiny streaming archive used for backup/restore. Not a general-purpose zip:
/// it stores files verbatim after a JSON manifest so restoring never needs to
/// hold the whole library in memory at once.
enum BackupArchive {
    static let magic = "QiyeBackup1\n"
    static let fileExtension = "qibackup"

    struct Entry: Codable, Equatable {
        let path: String
        let offset: UInt64
        let length: UInt64
    }

    struct Header: Codable {
        let version: Int
        let createdAt: Date
        let entries: [Entry]
    }

    enum Failure: LocalizedError {
        case invalidArchive
        case unsafePath(String)
        case missingFile(String)
        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "备份文件无法识别或已损坏。"
            case .unsafePath(let path): return "备份里含有不安全路径：\(path)"
            case .missingFile(let path): return "备份源文件缺失：\(path)"
            }
        }
    }

    /// Writes `files` (relative path → on-disk source) into a single archive at `destination`.
    static func write(files: [(path: String, url: URL)], to destination: URL) throws {
        var entries: [Entry] = []
        var offset: UInt64 = 0
        for file in files {
            let path = try sanitized(file.path)
            let size = try size(of: file.url)
            guard FileManager.default.fileExists(atPath: file.url.path) else { throw Failure.missingFile(path) }
            entries.append(Entry(path: path, offset: offset, length: size))
            offset += size
        }

        let header = Header(version: 1, createdAt: Date(), entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .iso8601
        var headerData = try encoder.encode(header)
        headerData.append(0x0A) // newline terminates the manifest

        let magicData = Data(magic.utf8)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.write(contentsOf: magicData)
        try output.write(contentsOf: headerData)

        let bufferSize = 1 << 20
        for file in files {
            let input = try FileHandle(forReadingFrom: file.url)
            defer { try? input.close() }
            while true {
                let chunk = try input.read(upToCount: bufferSize) ?? Data()
                if chunk.isEmpty { break }
                try output.write(contentsOf: chunk)
            }
        }
    }

    /// Reads the manifest from the start of an archive.
    static func readHeader(_ archive: URL) throws -> Header {
        try readManifest(archive).header
    }

    /// Restores every entry under `root`. Paths are sanitized again on the way out.
    static func extract(_ archive: URL, to root: URL) throws {
        let (header, payloadStart) = try readManifest(archive)
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }

        let bufferSize = 1 << 20
        for entry in header.entries {
            let relative = try sanitized(entry.path)
            let destination = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let output = try FileHandle(forWritingTo: destination)
            var remaining = entry.length
            var position = payloadStart + entry.offset
            do {
                while remaining > 0 {
                    try handle.seek(toOffset: position)
                    let wanted = Int(min(UInt64(bufferSize), remaining))
                    guard let chunk = try handle.read(upToCount: wanted), !chunk.isEmpty else { throw Failure.invalidArchive }
                    try output.write(contentsOf: chunk)
                    remaining -= UInt64(chunk.count)
                    position += UInt64(chunk.count)
                }
            } catch {
                try? output.close()
                throw error
            }
            try? output.close()
        }
    }

    /// Parses the magic + manifest line and returns the byte offset where payload starts.
    private static func readManifest(_ archive: URL) throws -> (header: Header, payloadStart: UInt64) {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        guard let prefix = try handle.read(upToCount: 1 << 20), prefix.count >= magic.count else {
            throw Failure.invalidArchive
        }
        let magicData = Data(magic.utf8)
        guard prefix.prefix(magicData.count) == magicData else { throw Failure.invalidArchive }
        let body = Data(prefix.dropFirst(magicData.count))
        guard let newline = body.firstIndex(of: 0x0A) else { throw Failure.invalidArchive }
        let headerData = body[body.startIndex..<newline]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header = try decoder.decode(Header.self, from: Data(headerData))
        guard header.version == 1 else { throw Failure.invalidArchive }
        // Header line length includes the newline byte itself.
        let payloadStart = UInt64(magicData.count + headerData.count + 1)
        return (header, payloadStart)
    }

    // MARK: - Helpers

    private static func sanitized(_ path: String) throws -> String {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let components = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relative.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }),
              !relative.contains(":") else {
            throw Failure.unsafePath(path)
        }
        return components.joined(separator: "/")
    }

    private static func size(of url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? NSNumber ?? 0
        return size.uint64Value
    }
}
