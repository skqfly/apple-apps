import Foundation

/// A single staged publishing operation. Everything here is committed at once from the home page.
struct PendingChange: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: Kind

    enum Kind: Codable, Equatable, Sendable {
        /// Publish a local photo draft. `source` is the public path, e.g. `/photos/qiye-<id>.jpg`.
        case addPhoto(photoID: String, source: String, imageName: String, width: Int, height: Int, alt: String)
        /// Remove a photo from the public list, keeping the image file.
        case unpublishPhoto(photoID: String, source: String)
        /// Remove a photo and its Qiye-uploaded image file.
        case deletePhoto(photoID: String, source: String)
        /// Publish a new talk. Talks have text and optional images, no title.
        case addTalk(talkID: String, text: String, date: Date, images: [TalkImageSpec], reusedSources: [String])
        /// Replace an existing talk's text, date and images.
        case editTalk(talkID: String, text: String, date: Date, keptSources: [String], newImages: [TalkImageSpec])
        /// Remove a talk from the public list, keeping its images.
        case unpublishTalk(talkID: String)
        /// Remove a talk and any Qiye-uploaded images it owns.
        case deleteTalk(talkID: String, imageSources: [String])

        struct TalkImageSpec: Codable, Equatable, Sendable {
            let imageName: String
            let width: Int
            let height: Int
        }
    }

    init(kind: Kind) {
        id = UUID()
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case id, kind }
    private enum LegacyKeys: String, CodingKey { case addTalk }
    private struct LegacyAddTalk: Decodable {
        let talkID: String
        let text: String
        let date: Date
        let images: [Kind.TalkImageSpec]
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        do { kind = try values.decode(Kind.self, forKey: .kind) }
        catch {
            let originalError = error
            let nested = try values.nestedContainer(keyedBy: LegacyKeys.self, forKey: .kind)
            guard nested.contains(.addTalk) else { throw originalError }
            let old = try nested.decode(LegacyAddTalk.self, forKey: .addTalk)
            kind = .addTalk(talkID: old.talkID, text: old.text, date: old.date, images: old.images, reusedSources: [])
        }
    }
}

extension PendingChange.Kind {
    /// Human readable summary shown on the home page.
    var label: String {
        switch self {
        case .addPhoto: return "新增照片"
        case .unpublishPhoto: return "下架照片"
        case .deletePhoto: return "删除照片"
        case .addTalk: return "新增说说"
        case .editTalk: return "编辑说说"
        case .unpublishTalk: return "下架说说"
        case .deleteTalk: return "删除说说"
        }
    }

    /// The repository file path to delete, but only for images this app uploaded.
    /// Trilium-managed media is shared and must never be removed by Qiye.
    static func repoDeletionPath(forSource source: String) -> String? {
        guard source.hasPrefix("/photos/qiye-") || source.hasPrefix("/talks/qiye-"),
              !source.contains("%"), !source.contains("?"), !source.contains("#"),
              !source.contains("\\"), source.hasSuffix(".jpg"),
              source.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }
        return "public" + source
    }
}

extension PendingChange.Kind {
    var contentKey: String {
        switch self {
        case .addTalk(let id, _, _, _, _), .editTalk(let id, _, _, _, _), .unpublishTalk(let id), .deleteTalk(let id, _):
            return "talk:" + id
        case .addPhoto(let id, _, _, _, _, _), .unpublishPhoto(let id, _), .deletePhoto(let id, _):
            return "photo:" + id
        }
    }

    var imageNames: [String] {
        switch self {
        case .addPhoto(_, _, let name, _, _, _): return name.isEmpty ? [] : [name]
        case .addTalk(_, _, _, let images, _), .editTalk(_, _, _, _, let images): return images.map(\.imageName)
        default: return []
        }
    }

    static func talkSource(talkID: String, image: TalkImageSpec) -> String {
        "/talks/\(talkID)/\(image.imageName)"
    }
}
