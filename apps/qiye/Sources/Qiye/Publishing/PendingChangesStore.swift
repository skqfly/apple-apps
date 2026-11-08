import Foundation
import Observation

@Observable @MainActor
final class PendingChangesStore {
    private(set) var changes: [PendingChange] = []
    private(set) var revision = 0
    private(set) var committedRevision = 0
    private(set) var isCommitting = false
    private(set) var error: String?
    private(set) var lastCommitSHA: String?
    var count: Int { changes.count }

    @ObservationIgnored private(set) var document = PublishingDocument()
    @ObservationIgnored private let imageDirectory: URL
    @ObservationIgnored private let metadataURL: URL
    @ObservationIgnored private var loadFailure: Error?
    @ObservationIgnored private var inFlightIDs: Set<UUID> = []
    @ObservationIgnored private let isFixture: Bool

    // A directory parameter also allows Foundation checks to inject write failures.
    init(directory: URL? = nil) {
        #if DEBUG
        let fixture = ProcessInfo.processInfo.arguments.contains("--uitest-content")
        #else
        let fixture = false
        #endif
        isFixture = fixture
        let defaultBase = URL.applicationSupportDirectory.appendingPathComponent("Publishing", isDirectory: true)
        let fixtureBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("QiyeContentUITests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            .appendingPathComponent("Publishing/ContentLibrary", isDirectory: true)
        let base = directory ?? (fixture ? fixtureBase : defaultBase)
        imageDirectory = base.appendingPathComponent("images", isDirectory: true)
        metadataURL = base.appendingPathComponent("changes.json")
        loadFromDisk()
    }

    func report(_ failure: Error) { error = failure.localizedDescription }

    // Publish the in-memory state only after the entire document reaches disk.
    func transaction(_ update: (inout PublishingDocument) throws -> Void) throws {
        do {
            if let loadFailure { throw loadFailure }
            var candidate = document
            try update(&candidate)
            try save(candidate)
            document = candidate
            changes = candidate.changes
            revision += 1
            error = nil
        } catch {
            report(error)
            throw error
        }
    }

    private func save(_ value: PublishingDocument) throws {
        try FileManager.default.createDirectory(at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: metadataURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return }
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let legacy = try? decoder.decode([PendingChange].self, from: data) {
                document.changes = legacy
            } else {
                document = try decoder.decode(PublishingDocument.self, from: data)
                guard document.version == 1 else { throw StagingFailure.invalidLocalData }
            }
            changes = document.changes
        } catch {
            // Never replace a corrupt/unreadable queue with an empty successful save.
            loadFailure = error
            report(error)
        }
    }

    private func checkMutable(key: String, in candidate: PublishingDocument) throws {
        if candidate.changes.contains(where: {
            $0.kind.contentKey == key && (inFlightIDs.contains($0.id) || candidate.unresolvedIDs.contains($0.id))
        }) { throw StagingFailure.operationUnresolved }
    }

    func replace(_ kind: PendingChange.Kind?, key: String, in candidate: inout PublishingDocument) throws {
        try checkMutable(key: key, in: candidate)
        let existing = candidate.changes.filter { $0.kind.contentKey == key }
        if existing.count == 1, existing.first?.kind == kind { return }
        candidate.changes.removeAll { $0.kind.contentKey == key }
        if let kind { candidate.changes.append(PendingChange(kind: kind)) }
    }

    // MARK: Existing staging API (nonthrowing legacy callers see error and no state mutation)

    func stagePhoto(draftID: UUID, jpeg: Data, width: Int, height: Int) throws {
        let id = "qiye-\(draftID.uuidString.lowercased())"
        if changes.contains(where: { if case .addPhoto(let current, _, _, _, _, _) = $0.kind { return current == id }; return false }) { return }
        let name = "\(id).jpg"
        try store(image: jpeg, named: name)
        try transaction { candidate in
            try replace(.addPhoto(photoID: id, source: "/photos/\(name)", imageName: name,
                                  width: width, height: height, alt: "照片"), key: "photo:" + id, in: &candidate)
        }
    }

    func stageUnpublishPhoto(photoID: String, source: String) {
        legacyStage(.unpublishPhoto(photoID: photoID, source: source))
    }
    func stageDeletePhoto(photoID: String, source: String) {
        legacyStage(.deletePhoto(photoID: photoID, source: source))
    }
    func stageUnpublishTalk(talkID: String) { legacyStage(.unpublishTalk(talkID: talkID)) }
    func stageDeleteTalk(talkID: String, imageSources: [String]) {
        legacyStage(.deleteTalk(talkID: talkID, imageSources: imageSources))
    }
    private func legacyStage(_ kind: PendingChange.Kind) {
        do { try transaction { try replace(kind, key: kind.contentKey, in: &$0) } }
        catch { report(error) }
    }

    func stageTalk(text: String, date: Date, images: [(jpeg: Data, width: Int, height: Int)], reusedSources: [String] = []) throws {
        let id = "qiye-\(UUID().uuidString.lowercased())"
        let specs = try storeTalkImages(talkID: id, images: images)
        try transaction { candidate in
            try replace(.addTalk(talkID: id, text: text, date: date, images: specs, reusedSources: reusedSources),
                        key: "talk:" + id, in: &candidate)
        }
    }

    func stageTalkEdit(talkID: String, text: String, date: Date, keptSources: [String], newImages: [(jpeg: Data, width: Int, height: Int)]) throws {
        let specs = try storeTalkImages(talkID: talkID, images: newImages)
        try transaction { candidate in
            let isAddition = candidate.changes.contains { if case .addTalk(let id, _, _, _, _) = $0.kind { return id == talkID }; return false }
            let kind: PendingChange.Kind = isAddition
                ? .addTalk(talkID: talkID, text: text, date: date, images: specs, reusedSources: keptSources)
                : .editTalk(talkID: talkID, text: text, date: date, keptSources: keptSources, newImages: specs)
            try replace(kind, key: "talk:" + talkID, in: &candidate)
        }
    }

    func remove(_ change: PendingChange) {
        do {
            try transaction { candidate in
                guard candidate.changes.contains(where: { $0.id == change.id }) else { return }
                try checkMutable(key: change.kind.contentKey, in: candidate)
                cancel(key: change.kind.contentKey, in: &candidate)
            }
            collectUnusedImages()
        } catch { report(error) }
    }

    func clear() {
        do {
            try transaction { candidate in
                for key in Set(candidate.changes.map { $0.kind.contentKey }) {
                    try checkMutable(key: key, in: candidate)
                    cancel(key: key, in: &candidate)
                }
            }
            collectUnusedImages()
        } catch { report(error) }
    }

    private func cancel(key: String, in candidate: inout PublishingDocument) {
        candidate.changes.removeAll { $0.kind.contentKey == key }
        if key.hasPrefix("talk:") {
            let id = String(key.dropFirst(5))
            if let undo = candidate.talkUndo.removeValue(forKey: id) { candidate.talks[id] = undo }
        } else {
            let id = String(key.dropFirst(6))
            if let undo = candidate.photoUndo.removeValue(forKey: id) { candidate.photos[id] = undo }
        }
    }

    // MARK: Library reconciliation

    func reconcileTalk(_ id: String, in candidate: inout PublishingDocument) throws {
        guard let record = candidate.talks[id] else { return }
        let key = "talk:" + id
        if record.purged {
            let sources = (record.remote?.images.map(\.src) ?? []) + (record.publishedSources ?? [])
            let owned = sources.filter { PendingChange.Kind.repoDeletionPath(forSource: $0) != nil }
            if record.remote != nil || !owned.isEmpty {
                try replace(.deleteTalk(talkID: id, imageSources: Array(Set(owned))), key: key, in: &candidate)
            } else {
                try replace(nil, key: key, in: &candidate)
                candidate.talks.removeValue(forKey: id)
                candidate.purgedTalkIDs.insert(id)
            }
        } else if record.state == .published {
            let normalized = publicTalk(record.post)
            if record.remote.map({ publicTalk($0) }) == normalized {
                try replace(nil, key: key, in: &candidate)
            } else {
                var local: [PendingChange.Kind.TalkImageSpec] = []
                var reused: [String] = []
                // Ordered reused paths preserve the editor's order. Local assets are
                // supplied separately by commitAll from the complete library record.
                for image in record.post.images {
                    if let url = image.originalURL, url.isFileURL {
                        let name = try ownedImageName(url)
                        local.append(.init(imageName: name, width: image.width ?? 1, height: image.height ?? 1))
                    }
                    reused.append(publicTalkSource(id: id, image: image))
                }
                // reusedSources carries the complete order. The manifest deduplicates
                // uploaded paths while retaining their dimensions from the specs.
                try replace(.addTalk(talkID: id, text: record.post.content, date: record.post.date,
                                     images: local, reusedSources: reused), key: key, in: &candidate)
            }
        } else {
            try replace(record.remote == nil ? nil : .unpublishTalk(talkID: id), key: key, in: &candidate)
        }
        if !candidate.hasChanges(for: key) { candidate.talkUndo.removeValue(forKey: id) }
    }

    func reconcilePhoto(_ id: String, in candidate: inout PublishingDocument) throws {
        guard let record = candidate.photos[id] else { return }
        let key = "photo:" + id
        if record.purged {
            if record.remote != nil || record.publishedSource != nil {
                try replace(.deletePhoto(photoID: id, source: record.publishedSource ?? record.photo.sourcePath), key: key, in: &candidate)
            } else {
                try replace(nil, key: key, in: &candidate)
                candidate.photos.removeValue(forKey: id)
                candidate.purgedPhotoIDs.insert(id)
            }
        } else if record.state == .published {
            if publicPhoto(record.photo) == record.remote {
                try replace(nil, key: key, in: &candidate)
            } else {
                let name = record.photo.src.isFileURL ? try ownedImageName(record.photo.src) : ""
                try replace(.addPhoto(photoID: id, source: record.photo.sourcePath, imageName: name,
                                      width: record.photo.width, height: record.photo.height, alt: record.photo.alt),
                            key: key, in: &candidate)
            }
        } else {
            try replace(record.remote == nil ? nil : .unpublishPhoto(photoID: id, source: record.photo.sourcePath),
                        key: key, in: &candidate)
        }
        if !candidate.hasChanges(for: key) { candidate.photoUndo.removeValue(forKey: id) }
    }

    private func publicTalkSource(id: String, image: TalkImage) -> String {
        if let url = image.originalURL, url.isFileURL {
            return PendingChange.Kind.talkSource(talkID: id, image: .init(imageName: url.lastPathComponent,
                                                                       width: image.width ?? 1, height: image.height ?? 1))
        }
        return image.src
    }

    private func publicTalk(_ post: TalkPost) -> TalkPost {
        TalkPost(id: post.id, title: "", date: post.date, description: post.content, images: post.images.map {
            let src = publicTalkSource(id: post.id, image: $0)
            return TalkImage(src: src, width: $0.width, height: $0.height, alt: "说说照片", preview: src, previewLarge: src)
        })
    }

    private func publicPhoto(_ photo: WebsitePhoto) -> WebsitePhoto {
        let url = URL(string: photo.sourcePath, relativeTo: GitHubRepository.websiteURL)!.absoluteURL
        return WebsitePhoto(id: photo.id, sourcePath: photo.sourcePath, src: url, width: photo.width,
                            height: photo.height, alt: photo.alt, preview: url, previewLarge: url)
    }

    // MARK: Commit

    @discardableResult
    func commitAll(repository: GitHubRepository) async throws -> String {
        guard !isFixture else { throw StagingFailure.fixturePublishingDisabled }
        guard !isCommitting else { throw StagingFailure.alreadyCommitting }
        guard !changes.isEmpty else { throw StagingFailure.nothingToCommit }
        isCommitting = true
        error = nil
        let snapshot = changes
        let ids = Set(snapshot.map(\.id))
        let newlyJournaled = ids.subtracting(document.unresolvedIDs)
        inFlightIDs = ids
        defer { isCommitting = false; inFlightIDs = [] }
        do {
            let assets = try assets(for: snapshot)
            // Journal before sending anything. An interrupted attempt remains retryable.
            try transaction { $0.unresolvedIDs.formUnion(ids) }
            let sha = try await repository.publishBatch(message: "Publish from Qiye", assets: assets) { head in
                try await self.buildBatch(snapshot: snapshot, repository: repository, head: head)
            }
            // Only acknowledge the captured IDs. New operations staged while awaiting
            // GitHub remain in the queue and their image files remain on disk.
            try transaction { candidate in
                for change in snapshot { acknowledge(change, in: &candidate) }
                candidate.changes.removeAll { ids.contains($0.id) }
                candidate.unresolvedIDs.subtract(ids)
            }
            lastCommitSHA = sha
            committedRevision += 1
            collectUnusedImages()
            return sha
        } catch {
            // publishUncertain is deliberately retained, including across restarts.
            // Other errors are known by GitHubRepository to precede a successful ref update.
            if let githubError = error as? GitHubError, case .publishUncertain = githubError {
                report(error)
                throw error
            }
            if !(error is CancellationError) {
                // A local acknowledgement failure after remote success must also retain
                // the journal. A retry applies the same IDs and immutable asset paths.
                if error is GitHubError { try? transaction { $0.unresolvedIDs.subtract(newlyJournaled) } }
            }
            report(error)
            throw error
        }
    }

    private func acknowledge(_ change: PendingChange, in candidate: inout PublishingDocument) {
        switch change.kind {
        case .addTalk(let id, _, _, _, _), .editTalk(let id, _, _, _, _):
            if var record = candidate.talks[id] {
                let remote = publicTalk(record.post)
                record.publishedSources = Array(Set((record.publishedSources ?? []) + (record.remote?.images.map(\.src) ?? []) + remote.images.map(\.src)))
                record.remote = remote
                candidate.talks[id] = record
            }
            candidate.talkUndo.removeValue(forKey: id)
        case .unpublishTalk(let id):
            candidate.talks[id]?.remote = nil
            candidate.talkUndo.removeValue(forKey: id)
        case .deleteTalk(let id, _):
            candidate.talks.removeValue(forKey: id)
            candidate.purgedTalkIDs.insert(id)
            candidate.talkUndo.removeValue(forKey: id)
        case .addPhoto(let id, _, _, _, _, _):
            if var record = candidate.photos[id] {
                record.remote = publicPhoto(record.photo)
                record.publishedSource = record.photo.sourcePath
                candidate.photos[id] = record
            }
            candidate.photoUndo.removeValue(forKey: id)
        case .unpublishPhoto(let id, _):
            candidate.photos[id]?.remote = nil
            candidate.photoUndo.removeValue(forKey: id)
        case .deletePhoto(let id, _):
            candidate.photos.removeValue(forKey: id)
            candidate.purgedPhotoIDs.insert(id)
            candidate.photoUndo.removeValue(forKey: id)
        }
    }

    private func assets(for snapshot: [PendingChange]) throws -> [String: Data] {
        var assets: [String: Data] = [:]
        for change in snapshot {
            switch change.kind {
            case .addPhoto(_, let source, let name, _, _, _):
                if !name.isEmpty { assets["public" + source] = try loadImage(named: name) }
            case .addTalk(let id, _, _, let images, _), .editTalk(let id, _, _, _, let images):
                for image in images {
                    assets["public" + PendingChange.Kind.talkSource(talkID: id, image: image)] = try loadImage(named: image.imageName)
                }
                if let record = document.talks[id] {
                    for image in record.post.images {
                        if let url = image.originalURL, url.isFileURL {
                            assets["public" + publicTalkSource(id: id, image: image)] = try loadImage(named: ownedImageName(url))
                        }
                    }
                }
            default: break
            }
        }
        return assets
    }

    private func buildBatch(snapshot: [PendingChange], repository: GitHubRepository, head: String) async throws -> GitHubRepository.BatchChange {
        // Both manifests and local archives protect shared images. The repository
        // additionally checks blog blobs in this head's immutable tree before deleting.
        let site = try await repository.getRepositoryFile(path: "src/data/site.json", ref: head)
        let photos = try await repository.getRepositoryFile(path: "src/data/photo-library.json", ref: head)
        var talkImages: [String: [TalkImage]] = [:]
        for record in document.talks.values where !record.purged {
            talkImages[record.post.id] = record.post.images
        }
        let retainedSources = document.talks.values.filter { !$0.purged }.flatMap { record in
            record.post.images.flatMap { image in
                [publicTalkSource(id: record.post.id, image: image), image.preview, image.previewLarge].compactMap { $0 }
            }
        } + document.photos.values.filter { !$0.purged }.flatMap {
            [$0.photo.sourcePath, $0.photo.preview.absoluteString, $0.photo.previewLarge.absoluteString]
        }
        return try PublishingManifest.apply(snapshot, site: site, photos: photos,
            talkImages: talkImages, retainedImageSources: retainedSources)
    }

    // MARK: Owned image files

    func imageURL(named name: String) -> URL { imageDirectory.appendingPathComponent(name) }

    private func validImageName(_ name: String) -> Bool {
        !name.isEmpty && name == URL(fileURLWithPath: name).lastPathComponent && !name.contains("/") && !name.contains("\\")
    }

    private func ownedImageName(_ url: URL) throws -> String {
        guard url.isFileURL, url.standardizedFileURL.deletingLastPathComponent() == imageDirectory.standardizedFileURL,
              validImageName(url.lastPathComponent) else { throw StagingFailure.foreignLocalImage }
        return url.lastPathComponent
    }

    func store(image: Data, named name: String) throws {
        if let loadFailure { throw loadFailure }
        guard validImageName(name) else { throw StagingFailure.missingImage }
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try image.write(to: imageURL(named: name), options: .atomic)
    }

    private func loadImage(named name: String) throws -> Data {
        guard validImageName(name), FileManager.default.fileExists(atPath: imageURL(named: name).path) else {
            throw StagingFailure.missingImage
        }
        return try Data(contentsOf: imageURL(named: name))
    }

    func storeTalkImages(talkID: String, images: [(jpeg: Data, width: Int, height: Int)]) throws -> [PendingChange.Kind.TalkImageSpec] {
        try images.map { image in
            guard image.width > 0, image.height > 0, !image.jpeg.isEmpty else { throw StagingFailure.missingImage }
            let name = "\(UUID().uuidString.lowercased()).jpg"
            try store(image: image.jpeg, named: name)
            return .init(imageName: name, width: image.width, height: image.height)
        }
    }

    func collectUnusedImages() {
        guard loadFailure == nil else { return }
        // Include undo records: cancelling an edit must be able to restore its images.
        let talks = Array(document.talks.values) + Array(document.talkUndo.values)
        let photos = Array(document.photos.values) + Array(document.photoUndo.values)
        var retained = Set(document.changes.flatMap { $0.kind.imageNames })
        for record in talks {
            for image in record.post.images {
                if let url = image.originalURL, url.isFileURL, let name = try? ownedImageName(url) { retained.insert(name) }
            }
        }
        for record in photos {
            if record.photo.src.isFileURL, let name = try? ownedImageName(record.photo.src) { retained.insert(name) }
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where !retained.contains(file.lastPathComponent) { try? FileManager.default.removeItem(at: file) }
    }

    enum StagingFailure: LocalizedError {
        case nothingToCommit, alreadyCommitting, missingImage, invalidSiteData, invalidPhotoData
        case operationUnresolved, purgedContent, mustDeleteFirst, invalidLocalData, foreignLocalImage, fixturePublishingDisabled
        var errorDescription: String? {
            switch self {
            case .nothingToCommit: return "没有待推送的变更。"
            case .alreadyCommitting: return "正在推送，请稍候。"
            case .missingImage: return "暂存的图片文件已丢失，请重新选择。"
            case .invalidSiteData: return "网站说说资料结构已变化，本次未修改文件。"
            case .invalidPhotoData: return "网站照片资料结构已变化，本次未修改文件。"
            case .operationUnresolved: return "这项变更正在推送或结果尚待确认，请先重试首页推送后再修改或撤销。"
            case .purgedContent: return "内容已经彻底删除。"
            case .mustDeleteFirst: return "请先将内容移入回收站，再确认彻底删除。"
            case .invalidLocalData: return "本地发布记录无法读取，原始文件已保留。"
            case .foreignLocalImage: return "图片不在内容库中，请重新导入。"
            case .fixturePublishingDisabled: return "截图测试内容不能推送到网站。"
            }
        }
    }
}
