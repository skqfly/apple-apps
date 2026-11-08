import Foundation
import Observation

// Queue and library share one atomic document, so a failed write changes neither.
enum ContentStatusFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case published, unpublished, deleted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .published: return "已发表"
        case .unpublished: return "未发表"
        case .deleted: return "已删除"
        }
    }
}

struct LibraryTalkRecord: Codable, Sendable {
    var post: TalkPost
    var state: ContentStatusFilter
    var remote: TalkPost?
    var publishedSources: [String]? = nil
    var purged = false
    var order: Int? = nil
}

struct LibraryPhotoRecord: Codable, Sendable {
    var photo: WebsitePhoto
    var state: ContentStatusFilter
    var remote: WebsitePhoto?
    var publishedSource: String? = nil
    var purged = false
    var order: Int? = nil
}

struct PublishingDocument: Codable {
    var version = 1
    var changes: [PendingChange] = []
    var talks: [String: LibraryTalkRecord] = [:]
    var photos: [String: LibraryPhotoRecord] = [:]
    var talkUndo: [String: LibraryTalkRecord] = [:]
    var photoUndo: [String: LibraryPhotoRecord] = [:]
    var purgedTalkIDs: Set<String> = []
    var purgedPhotoIDs: Set<String> = []
    // Written before a network attempt. After a crash/reply loss these operations
    // must be retried, not silently cancelled as though they never reached GitHub.
    var unresolvedIDs: Set<UUID> = []
}

@Observable @MainActor
final class ContentLibraryStore {
    @ObservationIgnored private let pending: PendingChangesStore
    var revision: Int { pending.revision }
    var error: String? { pending.error }

    init(pending: PendingChangesStore) { self.pending = pending }

    func syncTalks(_ posts: [TalkPost], authoritative: Bool = true) {
        do {
            try pending.transaction { document in
                for (offset, post) in posts.enumerated() where !document.purgedTalkIDs.contains(post.id) {
                    if var record = document.talks[post.id] {
                        guard authoritative else { continue }
                        guard !record.purged, record.state == .published,
                              !document.hasChanges(for: "talk:" + post.id) else { continue }
                        record.remote = post
                        record.order = offset
                        record.publishedSources = Array(Set((record.publishedSources ?? []) + post.images.map(\.src)))
                        if record.state == .published { record.post = post }
                        document.talks[post.id] = record
                    } else {
                        document.talks[post.id] = .init(post: post, state: .published, remote: post,
                                                        publishedSources: post.images.map(\.src), order: offset)
                    }
                }
            }
        } catch { pending.report(error) }
    }

    func syncPhotos(_ photos: [WebsitePhoto], authoritative: Bool = true) {
        do {
            try pending.transaction { document in
                for (offset, photo) in photos.enumerated() where !document.purgedPhotoIDs.contains(photo.id) {
                    if var record = document.photos[photo.id] {
                        guard authoritative else { continue }
                        guard !record.purged, record.state == .published,
                              !document.hasChanges(for: "photo:" + photo.id) else { continue }
                        record.remote = photo
                        record.publishedSource = photo.sourcePath
                        record.order = offset
                        if record.state == .published { record.photo = photo }
                        document.photos[photo.id] = record
                    } else {
                        document.photos[photo.id] = .init(photo: photo, state: .published, remote: photo,
                                                          publishedSource: photo.sourcePath, order: offset)
                    }
                }
            }
        } catch { pending.report(error) }
    }

    func talks(in state: ContentStatusFilter) -> [TalkPost] {
        _ = revision
        return pending.document.talks.values.filter { !$0.purged && $0.state == state }.sorted {
            if $0.post.date != $1.post.date { return $0.post.date > $1.post.date }
            if $0.order != $1.order { return ($0.order ?? Int.max) < ($1.order ?? Int.max) }
            return $0.post.id < $1.post.id
        }.map(\.post)
    }

    func photos(in state: ContentStatusFilter) -> [WebsitePhoto] {
        _ = revision
        return pending.document.photos.values.filter { !$0.purged && $0.state == state }.sorted {
            if $0.order != $1.order { return ($0.order ?? Int.max) < ($1.order ?? Int.max) }
            return $0.photo.id < $1.photo.id
        }.map(\.photo)
    }

    func stateOfTalk(_ id: String) -> ContentStatusFilter {
        _ = revision
        return pending.document.talks[id]?.state ?? .published
    }

    func stateOfPhoto(_ id: String) -> ContentStatusFilter {
        _ = revision
        return pending.document.photos[id]?.state ?? .published
    }

    func setTalkState(_ post: TalkPost, to state: ContentStatusFilter) throws {
        try pending.transaction { document in
            var record = document.talks[post.id] ?? .init(post: post, state: .published, remote: post)
            guard !record.purged else { throw PendingChangesStore.StagingFailure.purgedContent }
            document.rememberTalkUndo(record)
            record.state = state
            document.talks[post.id] = record
            try pending.reconcileTalk(post.id, in: &document)
        }
        pending.collectUnusedImages()
    }

    func setPhotoState(_ photo: WebsitePhoto, to state: ContentStatusFilter) throws {
        try pending.transaction { document in
            var record = document.photos[photo.id] ?? .init(photo: photo, state: .published, remote: photo)
            guard !record.purged else { throw PendingChangesStore.StagingFailure.purgedContent }
            document.rememberPhotoUndo(record)
            record.state = state
            document.photos[photo.id] = record
            try pending.reconcilePhoto(photo.id, in: &document)
        }
    }

    func restoreTalk(_ post: TalkPost) throws { try setTalkState(post, to: .unpublished) }
    func restorePhoto(_ photo: WebsitePhoto) throws { try setPhotoState(photo, to: .unpublished) }

    // UI calls these only after its separate destructive confirmation.
    func purgeTalk(_ post: TalkPost) throws {
        try pending.transaction { document in
            guard var record = document.talks[post.id], record.state == .deleted else {
                throw PendingChangesStore.StagingFailure.mustDeleteFirst
            }
            document.rememberTalkUndo(record)
            record.purged = true
            document.talks[post.id] = record
            try pending.reconcileTalk(post.id, in: &document)
        }
        pending.collectUnusedImages()
    }

    func purgePhoto(_ photo: WebsitePhoto) throws {
        try pending.transaction { document in
            guard var record = document.photos[photo.id], record.state == .deleted else {
                throw PendingChangesStore.StagingFailure.mustDeleteFirst
            }
            document.rememberPhotoUndo(record)
            record.purged = true
            document.photos[photo.id] = record
            try pending.reconcilePhoto(photo.id, in: &document)
        }
        pending.collectUnusedImages()
    }

    func saveTalk(text: String, date: Date, kept: [TalkImage], newImages: [(jpeg: Data, width: Int, height: Int)], editing: TalkPost?) throws {
        let id = editing?.id ?? "qiye-\(UUID().uuidString.lowercased())"
        let kept = try kept.map { image -> TalkImage in
            guard let url = image.originalURL, url.isFileURL else { return image }
            let owned = pending.imageURL(named: url.lastPathComponent)
            guard url.standardizedFileURL != owned.standardizedFileURL else { return image }
            let name = "\(UUID().uuidString.lowercased()).jpg"
            try pending.store(image: Data(contentsOf: url), named: name)
            return TalkImage(src: pending.imageURL(named: name).absoluteString,
                             width: image.width, height: image.height, alt: image.alt, preview: nil, previewLarge: nil)
        }
        let images = try pending.storeTalkImages(talkID: id, images: newImages)
        let localImages = images.map { image in
            TalkImage(src: pending.imageURL(named: image.imageName).absoluteString,
                      width: image.width, height: image.height, alt: "说说照片", preview: nil, previewLarge: nil)
        }
        do {
            try pending.transaction { document in
                let original = document.talks[id] ?? editing.map { LibraryTalkRecord(post: $0, state: .published, remote: $0) }
                if let original {
                    guard !original.purged else { throw PendingChangesStore.StagingFailure.purgedContent }
                    document.rememberTalkUndo(original)
                }
                let post = TalkPost(id: id, date: date, description: text, images: kept + localImages)
                document.talks[id] = .init(post: post, state: original?.state ?? .unpublished,
                                           remote: original?.remote, publishedSources: original?.publishedSources,
                                           order: original?.order ?? ((document.talks.values.compactMap(\.order).min() ?? 0) - 1))
                try pending.reconcileTalk(id, in: &document)
            }
        } catch {
            pending.collectUnusedImages()
            throw error
        }
    }

    func importPhoto(draft: PhotoDraft, url: URL) async throws {
        let id = "qiye-\(draft.id.uuidString.lowercased())"
        if pending.document.photos[id] != nil || pending.document.purgedPhotoIDs.contains(id) { return }
        #if canImport(ImageIO)
        let prepared = try await PhotoUploadPreparation.prepare(url: url)
        let data = prepared.data
        let width = prepared.width
        let height = prepared.height
        #else
        // Foundation verification supplies already prepared JPEG bytes.
        let data = try Data(contentsOf: url)
        let width = draft.width
        let height = draft.height
        #endif
        // Recheck after the await: two import tasks for the same draft are idempotent.
        if pending.document.photos[id] != nil || pending.document.purgedPhotoIDs.contains(id) { return }
        let name = "\(id)-\(UUID().uuidString.lowercased()).jpg"
        try pending.store(image: data, named: name)
        let ownURL = pending.imageURL(named: name)
        let photo = WebsitePhoto(id: id, sourcePath: "/photos/\(name)", src: ownURL,
                                 width: width, height: height, alt: draft.title,
                                 preview: ownURL, previewLarge: ownURL)
        do {
            try pending.transaction { document in
                document.photos[id] = .init(photo: photo, state: .unpublished, remote: nil,
                                            order: (document.photos.values.compactMap(\.order).min() ?? 0) - 1)
            }
        } catch {
            pending.collectUnusedImages()
            throw error
        }
    }
}

extension PublishingDocument {
    func hasChanges(for key: String) -> Bool { changes.contains { $0.kind.contentKey == key } }

    mutating func rememberTalkUndo(_ record: LibraryTalkRecord) {
        let key = "talk:" + record.post.id
        if !hasChanges(for: key) { talkUndo[record.post.id] = record }
    }

    mutating func rememberPhotoUndo(_ record: LibraryPhotoRecord) {
        let key = "photo:" + record.photo.id
        if !hasChanges(for: key) { photoUndo[record.photo.id] = record }
    }
}
