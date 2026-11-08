import Foundation

/// Pure Foundation transformation, also exercised by verify-library.swift.
enum PublishingManifest {
    static func apply(_ changes: [PendingChange], site: Data, photos: Data,
                      talkImages: [String: [TalkImage]] = [:], retainedImageSources: [String] = []) throws -> GitHubRepository.BatchChange {
        guard var root = try JSONSerialization.jsonObject(with: site) as? [String: Any],
              var page = root["talksPageContent"] as? [String: Any],
              var entries = page["entries"] as? [[String: Any]] else {
            throw PendingChangesStore.StagingFailure.invalidSiteData
        }
        guard var library = try JSONSerialization.jsonObject(with: photos) as? [String: Any],
              library.values.allSatisfy({ $0 is [String: Any] }) else {
            throw PendingChangesStore.StagingFailure.invalidPhotoData
        }
        var candidates: Set<String> = []
        var siteChanged = false
        var photosChanged = false
        for change in changes {
            switch change.kind {
            case .addTalk(let id, let text, let date, let images, let reused):
                siteChanged = true
                let previous = entries.first { $0["id"] as? String == id }
                let imageEntries = imageEntries(id: id, images: images, reused: reused, previous: previous, retained: talkImages[id] ?? [])
                // Replace by content ID: replay after an uncertain response never duplicates a talk.
                let index = entries.firstIndex { $0["id"] as? String == id } ?? 0
                entries.removeAll { $0["id"] as? String == id }
                entries.insert(["id": id, "title": "", "date": ContentDate.string(date),
                                "description": text, "images": imageEntries], at: min(index, entries.count))
            case .editTalk(let id, let text, let date, let kept, let images):
                siteChanged = true
                let previous = entries.first { $0["id"] as? String == id }
                let replacement: [String: Any] = ["id": id, "title": "", "date": ContentDate.string(date),
                    "description": text, "images": imageEntries(id: id, images: images, reused: kept, previous: previous, retained: talkImages[id] ?? [])]
                let index = entries.firstIndex { $0["id"] as? String == id } ?? 0
                entries.removeAll { $0["id"] as? String == id }
                entries.insert(replacement, at: min(index, entries.count))
            case .unpublishTalk(let id):
                siteChanged = true
                entries.removeAll { $0["id"] as? String == id }
            case .deleteTalk(let id, let sources):
                siteChanged = true
                entries.removeAll { $0["id"] as? String == id }
                candidates.formUnion(sources.compactMap { PendingChange.Kind.repoDeletionPath(forSource: $0) })
            case .addPhoto(let id, let source, _, let width, let height, let alt):
                photosChanged = true
                library[id] = ["src": source, "preview": source, "previewLarge": source,
                               "width": width, "height": height, "alt": alt]
            case .unpublishPhoto(let id, _):
                photosChanged = true
                library.removeValue(forKey: id)
            case .deletePhoto(let id, let source):
                photosChanged = true
                library.removeValue(forKey: id)
                if let path = PendingChange.Kind.repoDeletionPath(forSource: source) { candidates.insert(path) }
            }
        }
        page["entries"] = entries
        root["talksPageContent"] = page
        let references = referencedPaths(in: root).union(referencedPaths(in: library))
            .union(retainedImageSources.compactMap { PendingChange.Kind.repoDeletionPath(forSource: $0) })
        var files: [String: Data] = [:]
        if siteChanged { files["src/data/site.json"] = try json(root) }
        if photosChanged { files["src/data/photo-library.json"] = try json(library) }
        return GitHubRepository.BatchChange(files: files, deletions: candidates.subtracting(references).sorted())
    }

    private static func imageEntries(id: String, images: [PendingChange.Kind.TalkImageSpec], reused: [String], previous: [String: Any]?, retained: [TalkImage]) -> [[String: Any]] {
        var metadata: [String: [String: Any]] = [:]
        for entry in previous?["images"] as? [[String: Any]] ?? [] {
            if let src = entry["src"] as? String { metadata[src] = entry }
        }
        for image in retained {
            let src: String
            if let url = image.originalURL, url.isFileURL {
                src = PendingChange.Kind.talkSource(talkID: id, image: .init(imageName: url.lastPathComponent,
                    width: image.width ?? 1, height: image.height ?? 1))
            } else {
                src = image.src
            }
            // Local previews cannot be published. Remote previews survive restore/reuse.
            func preview(_ value: String?) -> String {
                guard let value, URL(string: value)?.isFileURL != true else { return src }
                return value
            }
            var entry: [String: Any] = ["src": src, "alt": image.alt ?? "说说照片",
                "preview": preview(image.preview), "previewLarge": preview(image.previewLarge ?? image.preview)]
            if let width = image.width { entry["width"] = width }
            if let height = image.height { entry["height"] = height }
            metadata[src] = entry
        }
        let uploaded = images.map { image -> String in
            let src = PendingChange.Kind.talkSource(talkID: id, image: image)
            if metadata[src] == nil {
                metadata[src] = ["src": src, "width": image.width, "height": image.height,
                                 "alt": "说说照片", "preview": src, "previewLarge": src]
            }
            return src
        }
        var seen: Set<String> = []
        return (reused + uploaded).compactMap { src in
            guard seen.insert(src).inserted else { return nil }
            return metadata[src] ?? ["src": src, "alt": "说说照片", "preview": src, "previewLarge": src]
        }
    }

    private static func referencedPaths(in value: Any) -> Set<String> {
        if let string = value as? String {
            return PendingChange.Kind.repoDeletionPath(forSource: string).map { Set([$0]) } ?? []
        }
        if let object = value as? [String: Any] {
            return object.values.reduce(into: Set<String>()) { $0.formUnion(referencedPaths(in: $1)) }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { $0.formUnion(referencedPaths(in: $1)) }
        }
        return []
    }

    private static func json(_ value: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
