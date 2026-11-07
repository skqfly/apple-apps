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

        // Old synthesized enum payload omitted reusedSources.
        let old: [String: Any] = ["id": UUID().uuidString, "kind": ["addTalk": ["talkID": "legacy", "text": "old", "date": "2026-01-02T00:00:00Z", "images": []]]]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(PendingChange.self, from: encoded(old))
        if case .addTalk(_, _, _, _, let reused) = migrated.kind {
            try check(reused.isEmpty, "legacy reused sources not defaulted")
        } else { throw CheckFailure(message: "wrong migrated operation") }

        // Replay produces the same manifest and cannot delete shared assets.
        let shared = "/photos/qiye-shared.jpg"
        let site = try encoded(["talksPageContent": ["entries": [["id": "other", "images": [["src": shared]]]]]])
        let photos = try encoded(["photo": ["src": shared]])
        let add = PendingChange(kind: .addTalk(talkID: "new", text: "hello", date: date,
            images: [.init(imageName: "immutable-uuid.jpg", width: 50, height: 40)], reusedSources: []))
        let remove = PendingChange(kind: .deletePhoto(photoID: "photo", source: shared))
        let batch = try PublishingManifest.apply([add, remove], site: site, photos: photos)
        try check(batch.deletions.isEmpty, "deleted an image referenced by another talk")
        let replay = try PublishingManifest.apply([add, remove], site: batch.files["src/data/site.json"]!, photos: batch.files["src/data/photo-library.json"]!)
        try check(batch.files == replay.files, "retry was not idempotent")
        try check(PendingChange.Kind.repoDeletionPath(forSource: "/photos/qiye-x/../secret.jpg") == nil, "unsafe deletion accepted")
        print("PASS: persisted states, restore, cancel, merge/order, pure-image drafts, disk failure, legacy queue, durable uncertain retry, idempotent manifest, shared-image protection")
    }
}
#endif
