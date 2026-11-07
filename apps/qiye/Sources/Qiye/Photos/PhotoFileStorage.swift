import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Serializes disk operations and keeps image processing off the main actor.
actor PhotoFileStorage {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func readDrafts(in directory: URL) throws -> [PhotoDraft] {
        let manifest = directory.appendingPathComponent("metadata.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        let drafts = try JSONDecoder().decode([PhotoDraft].self, from: Data(contentsOf: manifest))
        guard Set(drafts.map(\.id)).count == drafts.count,
              drafts.allSatisfy({ draft in
                  draft.filename == draft.id.uuidString + ".original" &&
                  draft.thumbnailFilename == draft.id.uuidString + ".thumbnail.jpg" &&
                  draft.width > 0 && draft.height > 0
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return drafts.sorted {
            $0.importedAt == $1.importedAt ? $0.id.uuidString < $1.id.uuidString : $0.importedAt > $1.importedAt
        }
    }

    func saveImage(_ data: Data) throws -> PhotoDraft {
        guard data.count <= 50 * 1_024 * 1_024 else { throw PhotoStorageError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw PhotoStorageError.invalidImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoStorageError.invalidImage
        }
        let thumbnailData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(thumbnailData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoStorageError.invalidImage
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoStorageError.invalidImage }
        let id = UUID()
        let draft = PhotoDraft(
            id: id, title: "本地照片", importedAt: Date(),
            filename: id.uuidString + ".original",
            thumbnailFilename: id.uuidString + ".thumbnail.jpg", width: width, height: height
        )
        let originalURL = directory.appendingPathComponent(draft.filename)
        let thumbnailURL = directory.appendingPathComponent(draft.thumbnailFilename)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try data.write(to: originalURL, options: .atomic)
            try (thumbnailData as Data).write(to: thumbnailURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: thumbnailURL)
            throw error
        }
        return draft
    }

    func writeMetadata(_ drafts: [PhotoDraft]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(drafts).write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
    }

    func removeFiles(for draft: PhotoDraft) throws {
        for filename in [draft.filename, draft.thumbnailFilename] {
            let url = directory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}

private enum PhotoStorageError: LocalizedError {
    case imageTooLarge
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .imageTooLarge: return "照片超过 50 MB，请选择较小的图片。"
        case .invalidImage: return "无法读取这张照片的图像内容。"
        }
    }
}
