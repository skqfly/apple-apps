// Compile with -D LIBRARY_VERIFICATION; excluded from application builds.
#if LIBRARY_VERIFICATION
import Foundation

private struct CheckFailure: Error { let message: String }
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(message: message) }
}
private func encoded(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

@main struct VerifyContentLibrary {
    @MainActor static func main() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let pending = PendingChangesStore(directory: base)
        let library = ContentLibraryStore(pending: pending)
        let date = ContentDate.parse("2026-01-02")!
        let first = TalkPost(id: "z-first", date: date, description: "first", images: [])
        let second = TalkPost(id: "a-second", date: date, description: "second", images: [])
        library.syncTalks([first, second])
        try check(library.talks(in: .published).map(\.id) == [first.id, second.id], "same-date input order lost")
        try library.setTalkState(first, to: .deleted)
        try check(library.stateOfTalk(first.id) == .deleted && pending.count == 1, "trash must unpublish")
        pending.remove(pending.changes[0])
        try check(library.stateOfTalk(first.id) == .published && pending.count == 0, "cancellation did not restore state")
        try library.setTalkState(first, to: .unpublished)
        try library.setTalkState(first, to: .published)
        try check(pending.count == 0, "unpublish/re-publish should cancel before push")
        try library.setTalkState(first, to: .deleted)
        try library.restoreTalk(first)
        try check(library.stateOfTalk(first.id) == .unpublished, "restore must be unpublished")
        library.syncTalks([first])
        try check(library.stateOfTalk(first.id) == .unpublished, "stale bundled snapshot resurrected archive")
        try check(library.stateOfTalk(second.id) == .published, "partial snapshot unpublished missing IDs")
        let reopened = ContentLibraryStore(pending: PendingChangesStore(directory: base))
        try check(reopened.stateOfTalk(first.id) == .unpublished, "state did not survive reload")
        try library.saveTalk(text: "", date: date, kept: [], newImages: [(Data([0xFF, 0xD8, 0xFF]), 40, 30)], editing: nil)
        let draft = library.talks(in: .unpublished).first { $0.id.hasPrefix("qiye-") }!
        try check(draft.images.first?.url?.isFileURL == true, "draft image URL not loadable")
        try check(!pending.changes.contains { $0.kind.contentKey == "talk:" + draft.id }, "new draft staged prematurely")
        try library.setTalkState(draft, to: .published)
        let count = pending.count
        let operation = pending.changes.last!
        try library.setTalkState(draft, to: .published)
        try check(pending.count == count && pending.changes.last!.id == operation.id, "repeated stage changed operation identity")
        try pending.transaction { $0.unresolvedIDs.insert(operation.id) }
        pending.remove(operation)
        try check(pending.changes.contains { $0.id == operation.id } && pending.error != nil, "uncertain request could be discarded")
        let reloadedPending = PendingChangesStore(directory: base)
        try check(reloadedPending.document.unresolvedIDs.contains(operation.id), "uncertain journal not durable")

        // A persistence failure must not change memory or report a successful stage.
        let blocked = base.appendingPathComponent("blocked")
        try Data([1]).write(to: blocked)
        let broken = PendingChangesStore(directory: blocked)
        broken.stageUnpublishTalk(talkID: "unchanged")
        try check(broken.count == 0 && broken.error != nil, "failed disk write pretended success")

        // A corrupt document must never turn an unknown reference set into garbage collection.
        let corruptBase = base.appendingPathComponent("corrupt")
        let corruptImages = corruptBase.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: corruptImages, withIntermediateDirectories: true)
        let retainedImage = corruptImages.appendingPathComponent("retained.jpg")
        let retainedBytes = Data([0xFF, 0xD8, 0xFF])
        try retainedBytes.write(to: retainedImage)
        let corruptJSON = Data("{broken".utf8)
        try corruptJSON.write(to: corruptBase.appendingPathComponent("changes.json"))
        let corrupt = PendingChangesStore(directory: corruptBase)
        let corruptLibrary = ContentLibraryStore(pending: corrupt)
        do {
            try corruptLibrary.saveTalk(text: "cannot save", date: date, kept: [], newImages: [], editing: nil)
            throw CheckFailure(message: "corrupt document accepted a save")
        } catch is CheckFailure { throw CheckFailure(message: "corrupt document accepted a save") }
        catch { }
        corrupt.collectUnusedImages()
        let bytesAfterFailure = try Data(contentsOf: retainedImage)
        try check(bytesAfterFailure == retainedBytes, "failed save after corrupt load deleted archived image")
        do {
            try corrupt.store(image: Data([1]), named: "new.jpg")
            throw CheckFailure(message: "corrupt document accepted an image write")
        } catch is CheckFailure { throw CheckFailure(message: "corrupt document accepted an image write") }
        catch { }
        let metadataAfterFailure = try Data(contentsOf: corruptBase.appendingPathComponent("changes.json"))
        try check(metadataAfterFailure == corruptJSON, "corrupt metadata was overwritten")

        // Persisted published records win over bundled/failed-refresh snapshots on reopen.
        let snapshotBase = base.appendingPathComponent("snapshots")
        let snapshots = ContentLibraryStore(pending: PendingChangesStore(directory: snapshotBase))
        let latestTalk = TalkPost(id: "snapshot", date: date, description: "latest", images: [])
        snapshots.syncTalks([latestTalk])
        let latestURL = URL(string: "https://mmddskq.top/photos/qiye-latest.jpg")!
        let latestPhoto = WebsitePhoto(id: "snapshot-photo", src: latestURL, width: 80, height: 60,
            alt: "latest", preview: latestURL, previewLarge: latestURL)
        snapshots.syncPhotos([latestPhoto])
        let reopenedSnapshots = ContentLibraryStore(pending: PendingChangesStore(directory: snapshotBase))
        let staleTalk = TalkPost(id: latestTalk.id, date: date, description: "bundled", images: [])
        reopenedSnapshots.syncTalks([staleTalk], authoritative: false)
        let stalePhoto = WebsitePhoto(id: latestPhoto.id, src: latestURL, width: 1, height: 1,
            alt: "bundled", preview: latestURL, previewLarge: latestURL)
        reopenedSnapshots.syncPhotos([stalePhoto], authoritative: false)
        try check(reopenedSnapshots.talks(in: .published).first == latestTalk, "bundled talk overwrote persisted edit")
        try check(reopenedSnapshots.photos(in: .published).first == latestPhoto, "bundled photo overwrote persisted record")
        reopenedSnapshots.syncTalks([staleTalk], authoritative: true)
        try check(reopenedSnapshots.talks(in: .published).first == staleTalk, "fresh network snapshot was ignored")

        // Old synthesized enum payload omitted reusedSources.
        let old: [String: Any] = ["id": UUID().uuidString, "kind": ["addTalk": ["talkID": "legacy", "text": "old", "date": "2026-01-02T00:00:00Z", "images": []]]]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(PendingChange.self, from: encoded(old))
        if case .addTalk(_, _, _, _, let reused) = migrated.kind {
            try check(reused.isEmpty, "legacy reused sources not defaulted")
        } else { throw CheckFailure(message: "wrong migrated operation") }

        let shared = "/photos/qiye-shared.jpg"
        let photos = try encoded(["photo": ["src": shared]])
        let remove = PendingChange(kind: .deletePhoto(photoID: "photo", source: shared))
        let emptySite = try encoded(["talksPageContent": ["entries": [] as [[String: Any]]]])
        let emptyPhotos = try encoded([String: String]())
        let absoluteShared = "https://mmddskq.top" + shared
        try check(PendingChange.Kind.repoDeletionPath(forSource: absoluteShared) == "public" + shared,
                  "absolute site image did not normalize")
        try check(PendingChange.Kind.repoDeletionPath(forSource: absoluteShared + "?v=1#photo") == "public" + shared,
                  "query/fragment reference did not protect source")
        try check(PendingChange.Kind.repoDeletionPath(forSource: "https://other.example" + shared) == nil,
                  "foreign origin was treated as an owned image")
        try check(PendingChange.Kind.repoDeletionPath(forSource: "https://mmddskq.top/photos/qiye-x/../secret.jpg") == nil,
                  "absolute traversal accepted")
        try check(PendingChange.Kind.repoDeletionPath(forSource: "/photos/qiye-%2e%2e/secret.jpg") == nil,
                  "encoded traversal accepted")
        let archiveProtected = try PublishingManifest.apply([remove], site: emptySite, photos: photos,
            retainedImageSources: [absoluteShared])
        try check(archiveProtected.deletions.isEmpty, "absolute archive reference did not protect shared image")
        let absoluteSite = try encoded(["talksPageContent": ["entries": [["id": "absolute", "images": [["src": absoluteShared]]]]]])
        let publicProtected = try PublishingManifest.apply([remove], site: absoluteSite, photos: photos)
        try check(publicProtected.deletions.isEmpty, "absolute manifest reference did not protect shared image")
        let candidate = "public" + shared
        try check(GitHubRepository.unreferencedImageDeletions([candidate], blogContents: ["image: {\"url\":\"\(absoluteShared)\"}"]).isEmpty,
                  "blog frontmatter reference was deleted")
        try check(GitHubRepository.unreferencedImageDeletions([candidate], blogContents: ["![shared](\(shared))"]).isEmpty,
                  "blog body reference was deleted")
        try check(GitHubRepository.unreferencedImageDeletions([candidate], blogContents: nil).isEmpty,
                  "unreadable/truncated blog scan allowed deletion")
        try check(GitHubRepository.unreferencedImageDeletions([candidate], blogContents: ["unrelated"]) == [candidate],
                  "unreferenced image could not be collected")

        // Restoring a remotely sourced image must not rely on a previous public entry.
        let reusedImage = TalkImage(src: shared, width: 640, height: 480, alt: "original caption",
            preview: "/photos/qiye-shared-preview.jpg", previewLarge: "/photos/qiye-shared-large.jpg")
        let restored = PendingChange(kind: .addTalk(talkID: "restored", text: "restored", date: date,
            images: [], reusedSources: [shared]))
        let restoredBatch = try PublishingManifest.apply([restored], site: emptySite, photos: emptyPhotos,
            talkImages: ["restored": [reusedImage]])
        let restoredJSON = try JSONSerialization.jsonObject(with: restoredBatch.files["src/data/site.json"]!) as! [String: Any]
        let restoredPage = restoredJSON["talksPageContent"] as! [String: Any]
        let restoredEntries = restoredPage["entries"] as! [[String: Any]]
        let restoredImages = restoredEntries[0]["images"] as! [[String: Any]]
        try check(restoredImages[0]["width"] as? Int == 640 && restoredImages[0]["height"] as? Int == 480,
                  "restored remote image lost dimensions")
        try check(restoredImages[0]["alt"] as? String == reusedImage.alt &&
                  restoredImages[0]["preview"] as? String == reusedImage.preview &&
                  restoredImages[0]["previewLarge"] as? String == reusedImage.previewLarge,
                  "restored remote image lost caption/previews")
        let restoredReplay = try PublishingManifest.apply([restored], site: restoredBatch.files["src/data/site.json"]!, photos: emptyPhotos,
            talkImages: ["restored": [reusedImage]])
        try check(restoredReplay.files == restoredBatch.files, "restored metadata changed on retry")
        let localImage = TalkImage(src: "file:///tmp/library/local.jpg", width: 90, height: 60, alt: "local caption",
            preview: "file:///tmp/library/preview.jpg", previewLarge: nil)
        let localSpec = PendingChange.Kind.TalkImageSpec(imageName: "local.jpg", width: 90, height: 60)
        let localSource = PendingChange.Kind.talkSource(talkID: "local", image: localSpec)
        let localAdd = PendingChange(kind: .addTalk(talkID: "local", text: "local", date: date,
            images: [localSpec], reusedSources: [localSource, shared]))
        let localBatch = try PublishingManifest.apply([localAdd], site: emptySite, photos: emptyPhotos,
            talkImages: ["local": [localImage, reusedImage]])
        let localJSON = try JSONSerialization.jsonObject(with: localBatch.files["src/data/site.json"]!) as! [String: Any]
        let localPage = localJSON["talksPageContent"] as! [String: Any]
        let localEntries = localPage["entries"] as! [[String: Any]]
        let localImages = localEntries[0]["images"] as! [[String: Any]]
        try check(localImages.compactMap { $0["src"] as? String } == [localSource, shared], "mixed image order lost")
        try check(localImages[0]["preview"] as? String == localSource && localImages[0]["previewLarge"] as? String == localSource,
                  "local file URL leaked into public previews")
        try check(localImages[0]["alt"] as? String == "local caption", "upload replaced complete local metadata")

        // Replay produces the same manifest and cannot delete shared assets.
        let site = try encoded(["talksPageContent": ["entries": [["id": "other", "images": [["src": shared]]]]]])
        let add = PendingChange(kind: .addTalk(talkID: "new", text: "hello", date: date,
            images: [.init(imageName: "immutable-uuid.jpg", width: 50, height: 40)], reusedSources: []))
        let batch = try PublishingManifest.apply([add, remove], site: site, photos: photos)
        try check(batch.deletions.isEmpty, "deleted an image referenced by another talk")
        let replay = try PublishingManifest.apply([add, remove], site: batch.files["src/data/site.json"]!, photos: batch.files["src/data/photo-library.json"]!)
        try check(batch.files == replay.files, "retry was not idempotent")
        try check(PendingChange.Kind.repoDeletionPath(forSource: "/photos/qiye-x/../secret.jpg") == nil, "unsafe deletion accepted")

        // Published order follows the drag result and survives reopening.
        let orderBase = base.appendingPathComponent("photo-order")
        let orderPending = PendingChangesStore(directory: orderBase)
        let orderLibrary = ContentLibraryStore(pending: orderPending)
        func photo(_ id: String) -> WebsitePhoto {
            let url = URL(string: "https://mmddskq.top/photos/\(id).jpg")!
            return WebsitePhoto(id: id, src: url, width: 20, height: 20, alt: id, preview: url, previewLarge: url)
        }
        orderLibrary.syncPhotos(["z-last", "m-middle", "a-first"].map(photo))
        try orderLibrary.movePhoto("a-first", before: "z-last")
        try check(orderLibrary.photos(in: .published).map(\.id) == ["a-first", "z-last", "m-middle"], "drag did not move before target")
        guard let orderOperation = orderPending.changes.last else {
            throw CheckFailure(message: "no staged changes: \(orderPending.error ?? "nil")")
        }
        if case .reorderPhotos(let ids) = orderOperation.kind {
            try check(ids == ["a-first", "z-last", "m-middle"], "website order operation differs from wall")
        } else { throw CheckFailure(message: "published drag did not stage website order") }
        let reopenedOrder = ContentLibraryStore(pending: PendingChangesStore(directory: orderBase))
        try check(reopenedOrder.photos(in: .published).map(\.id) == ["a-first", "z-last", "m-middle"], "photo order did not persist")
        try orderLibrary.movePhoto("a-first", before: "z-last")
        try check(orderPending.changes.last?.id == orderOperation.id, "same order created another operation")
        try orderLibrary.movePhoto("a-first", before: nil)
        try orderLibrary.movePhoto("z-last", before: "m-middle")
        try orderLibrary.movePhoto("a-first", before: "z-last")
        try check(orderPending.count == 0, "returning to remote order left a pending change")

        let libraryJSON = try encoded(["z-last": ["src": "/z"], "m-middle": ["src": "/m"], "a-first": ["src": "/a"], "kept": ["src": "/k"]])
        let orderedBatch = try PublishingManifest.apply([orderOperation], site: emptySite, photos: libraryJSON)
        let orderedObject = try JSONSerialization.jsonObject(with: orderedBatch.files["src/data/photo-library.json"]!) as! [String: Any]
        try check(Array(orderedObject.keys) == ["a-first", "z-last", "m-middle", "kept"], "website JSON did not preserve drag order")
        let orderReplay = try PublishingManifest.apply([orderOperation], site: emptySite, photos: orderedBatch.files["src/data/photo-library.json"]!)
        try check(orderReplay.files == orderedBatch.files, "photo order changed when retried")

        print("PASS: persisted states, restore, cancel, merge/order, pure-image drafts, disk failure, corrupt-load image protection, snapshot authority, legacy queue, durable uncertain retry, idempotent manifest, absolute/archive/blog shared-image protection, complete reused metadata, public preview URLs, drag photo order")
    }
}
#endif
