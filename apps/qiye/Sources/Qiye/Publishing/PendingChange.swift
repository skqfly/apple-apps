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
        guard source.hasPrefix("/photos/qiye-") || source.hasPrefix("/talks/qiye-") else { return nil }
        return "public" + source
    }
}
