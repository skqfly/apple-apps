import Foundation
import Observation
import UIKit

@Observable @MainActor
final class PendingChangesStore {
    private(set) var changes: [PendingChange] = []
    private(set) var revision = 0
    private(set) var committedRevision = 0
    private(set) var isCommitting = false
    private(set) var error: String?
    private(set) var lastCommitSHA: String?

    var count: Int { changes.count }

    @ObservationIgnored private let imageDirectory: URL
    @ObservationIgnored private let metadataURL: URL

    init() {
        let base = URL.applicationSupportDirectory.appendingPathComponent("Publishing", isDirectory: true)
        imageDirectory = base.appendingPathComponent("images", isDirectory: true)
        metadataURL = base.appendingPathComponent("changes.json")
        loadFromDisk()
    }

    // MARK: - Staging

    func stagePhoto(draftID: UUID, jpeg: Data, width: Int, height: Int) throws {
        let photoID = "qiye-\(draftID.uuidString.lowercased())"
        let source = "/photos/\(photoID).jpg"
        let imageName = "\(photoID).jpg"
        try store(image: jpeg, named: imageName)
        changes.append(PendingChange(kind: .addPhoto(
            photoID: photoID, source: source, imageName: imageName,
            width: width, height: height, alt: "照片"
        )))
        bump()
    }

    func stageUnpublishPhoto(photoID: String, source: String) {
        changes.append(PendingChange(kind: .unpublishPhoto(photoID: photoID, source: source)))
        bump()
    }

    func stageDeletePhoto(photoID: String, source: String) {
        changes.append(PendingChange(kind: .deletePhoto(photoID: photoID, source: source)))
        bump()
    }

    func stageTalk(text: String, date: Date, images: [(jpeg: Data, width: Int, height: Int)], reusedSources: [String] = []) throws {
        let talkID = "qiye-\(UUID().uuidString.lowercased())"
        let specs = try storeTalkImages(talkID: talkID, images: images)
        changes.append(PendingChange(kind: .addTalk(
            talkID: talkID, text: text, date: date, images: specs, reusedSources: reusedSources
        )))
        bump()
    }

    /// Edits an existing talk. `keptSources` are images already on the site; `newImages` are newly added.
    func stageTalkEdit(talkID: String, text: String, date: Date, keptSources: [String], newImages: [(jpeg: Data, width: Int, height: Int)]) throws {
        let specs = try storeTalkImages(talkID: talkID, images: newImages)
        changes.removeAll { change in
            if case .editTalk(let id, _, _, _, _) = change.kind { return id == talkID }
            return false
        }
        changes.append(PendingChange(kind: .editTalk(
            talkID: talkID, text: text, date: date, keptSources: keptSources, newImages: specs
        )))
        bump()
    }

    private func storeTalkImages(talkID: String, images: [(jpeg: Data, width: Int, height: Int)]) throws -> [PendingChange.Kind.TalkImageSpec] {
        var specs: [PendingChange.Kind.TalkImageSpec] = []
        for (index, image) in images.enumerated() {
            let name = "\(talkID)-\(index)-\(UUID().uuidString.lowercased()).jpg"
            try store(image: image.jpeg, named: name)
            specs.append(.init(imageName: name, width: image.width, height: image.height))
        }
        return specs
    }

    func stageUnpublishTalk(talkID: String) {
        changes.append(PendingChange(kind: .unpublishTalk(talkID: talkID)))
        bump()
    }

    func stageDeleteTalk(talkID: String, imageSources: [String]) {
        changes.append(PendingChange(kind: .deleteTalk(talkID: talkID, imageSources: imageSources)))
        bump()
    }

    func remove(_ change: PendingChange) {
        changes.removeAll { $0.id == change.id }
        imageNames(in: change).forEach { discardImage(named: $0) }
        bump()
    }

    func clear() {
        changes.flatMap(imageNames).forEach { discardImage(named: $0) }
        changes.removeAll()
        bump()
    }

    private func imageNames(in change: PendingChange) -> [String] {
        switch change.kind {
        case .addPhoto(_, _, let name, _, _, _): return [name]
        case .addTalk(_, _, _, let images, _): return images.map(\.imageName)
        case .editTalk(_, _, _, _, let images): return images.map(\.imageName)
        default: return []
        }
    }

    // MARK: - Commit

    @discardableResult
    func commitAll(repository: GitHubRepository) async throws -> String {
        guard !isCommitting else { throw StagingFailure.alreadyCommitting }
        guard !changes.isEmpty else { throw StagingFailure.nothingToCommit }
        isCommitting = true
        error = nil
        defer { isCommitting = false }
        let snapshot = changes

        var assets: [String: Data] = [:]
        for change in snapshot {
            switch change.kind {
            case .addPhoto(_, let source, let imageName, _, _, _):
                assets["public\(source)"] = try loadImage(named: imageName)
            case .addTalk(let talkID, _, _, let images, _):
                for (index, image) in images.enumerated() {
                    assets["public/talks/\(talkID)/\(index).jpg"] = try loadImage(named: image.imageName)
                }
            case .editTalk(let talkID, _, _, _, let images):
                for (index, image) in images.enumerated() {
                    assets["public/talks/\(talkID)/edit-\(index).jpg"] = try loadImage(named: image.imageName)
                }
            default: break
            }
        }

        do {
            let sha = try await repository.publishBatch(
                message: "Publish from Qiye",
                assets: assets
            ) { head in
                try await self.buildBatch(snapshot: snapshot, repository: repository, head: head)
            }
            lastCommitSHA = sha
            committedRevision += 1
            clear()
            return sha
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    private func buildBatch(
        snapshot: [PendingChange], repository: GitHubRepository, head: String
    ) async throws -> GitHubRepository.BatchChange {
        var deletions: [String] = []
        var files: [String: Data] = [:]

        let siteChanged = snapshot.contains {
            switch $0.kind {
            case .addTalk, .editTalk, .unpublishTalk, .deleteTalk: return true
            default: return false
            }
        }
        let photosChanged = snapshot.contains {
            if case .addPhoto = $0.kind { return true }
            if case .unpublishPhoto = $0.kind { return true }
            if case .deletePhoto = $0.kind { return true }
            return false
        }

        if siteChanged {
            let data = try await repository.getRepositoryFile(path: "src/data/site.json", ref: head)
            files["src/data/site.json"] = try applyTalks(snapshot: snapshot, data: data, deletions: &deletions)
        }
        if photosChanged {
            let data = try await repository.getRepositoryFile(path: "src/data/photo-library.json", ref: head)
            files["src/data/photo-library.json"] = try applyPhotos(snapshot: snapshot, data: data, deletions: &deletions)
        }
        return GitHubRepository.BatchChange(files: files, deletions: deletions)
    }

    private func applyTalks(snapshot: [PendingChange], data: Data, deletions: inout [String]) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var page = root["talksPageContent"] as? [String: Any],
              var entries = page["entries"] as? [[String: Any]] else {
            throw StagingFailure.invalidSiteData
        }
        for change in snapshot {
            switch change.kind {
            case .addTalk(let talkID, let text, let date, let images, let reused):
                let uploaded = images.enumerated().map { index, image -> [String: Any] in
                    let src = "/talks/\(talkID)/\(index).jpg"
                    return ["src": src, "width": image.width, "height": image.height,
                            "alt": "说说照片", "preview": src, "previewLarge": src]
                }
                let reusedEntries = reused.map { ["src": $0, "alt": "说说照片", "preview": $0, "previewLarge": $0] }
                entries.insert(["id": talkID, "title": "", "date": ContentDate.string(date),
                                "description": text, "images": reusedEntries + uploaded], at: 0)
            case .editTalk(let talkID, let text, let date, let kept, let images):
                guard let index = entries.firstIndex(where: { ($0["id"] as? String) == talkID }) else { break }
                let keptEntries = kept.map { ["src": $0, "alt": "说说照片", "preview": $0, "previewLarge": $0] }
                let uploaded = images.enumerated().map { offset, image -> [String: Any] in
                    let src = "/talks/\(talkID)/edit-\(offset).jpg"
                    return ["src": src, "width": image.width, "height": image.height,
                            "alt": "说说照片", "preview": src, "previewLarge": src]
                }
                entries[index]["title"] = ""
                entries[index]["date"] = ContentDate.string(date)
                entries[index]["description"] = text
                entries[index]["images"] = keptEntries + uploaded
            case .unpublishTalk(let talkID):
                entries.removeAll { ($0["id"] as? String) == talkID }
            case .deleteTalk(let talkID, let imageSources):
                entries.removeAll { ($0["id"] as? String) == talkID }
                for source in imageSources {
                    if let path = PendingChange.Kind.repoDeletionPath(forSource: source) { deletions.append(path) }
                }
            default: break
            }
        }
        page["entries"] = entries
        root["talksPageContent"] = page
        return try Self.json(root)
    }

    private static func talkEntry(id: String, text: String, date: Date, images: [PendingChange.Kind.TalkImageSpec], prefix: String) -> [String: Any] {
        let imageEntries: [[String: Any]] = images.enumerated().map { index, image in
            let src = prefix + "\(index).jpg"
            return ["src": src, "width": image.width, "height": image.height,
                    "alt": "说说照片", "preview": src, "previewLarge": src]
        }
        return ["id": id, "title": "", "date": ContentDate.string(date), "description": text, "images": imageEntries]
    }

    private func applyPhotos(snapshot: [PendingChange], data: Data, deletions: inout [String]) throws -> Data {
        guard var library = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StagingFailure.invalidPhotoData
        }
        for change in snapshot {
            switch change.kind {
            case .addPhoto(let photoID, let source, _, let width, let height, let alt):
                library[photoID] = ["src": source, "preview": source, "previewLarge": source,
                                    "width": width, "height": height, "alt": alt]
            case .unpublishPhoto(let photoID, _):
                library.removeValue(forKey: photoID)
            case .deletePhoto(let photoID, let source):
                library.removeValue(forKey: photoID)
                if let path = PendingChange.Kind.repoDeletionPath(forSource: source) { deletions.append(path) }
            default: break
            }
        }
        return try Self.json(library)
    }

    private static func json(_ value: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    // MARK: - Image storage

    private func store(image: Data, named name: String) throws {
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try image.write(to: imageDirectory.appendingPathComponent(name), options: .atomic)
    }

    private func loadImage(named name: String) throws -> Data {
        let url = imageDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw StagingFailure.missingImage }
        return try Data(contentsOf: url)
    }

    private func discardImage(named name: String) {
        try? FileManager.default.removeItem(at: imageDirectory.appendingPathComponent(name))
    }

    // MARK: - Persistence

    private func bump() {
        revision += 1
        saveToDisk()
    }

    private func saveToDisk() {
        do {
            try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(changes).write(to: metadataURL, options: .atomic)
        } catch {
            // Staging remains in memory even if persistence fails.
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode([PendingChange].self, from: data) {
            changes = saved
        }
    }

    enum StagingFailure: LocalizedError {
        case nothingToCommit, alreadyCommitting, missingImage, invalidSiteData, invalidPhotoData
        var errorDescription: String? {
            switch self {
            case .nothingToCommit: return "没有待推送的变更。"
            case .alreadyCommitting: return "正在推送，请稍候。"
            case .missingImage: return "暂存的图片文件已丢失，请重新选择。"
            case .invalidSiteData: return "网站说说资料结构已变化，本次未修改文件。"
            case .invalidPhotoData: return "网站照片资料结构已变化，本次未修改文件。"
            }
        }
    }
}
