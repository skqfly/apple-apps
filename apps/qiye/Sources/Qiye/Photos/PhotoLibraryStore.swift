import Foundation
import Observation
import SwiftUI
import PhotosUI

@Observable
@MainActor
final class PhotoLibraryStore {
    private(set) var photos: [WebsitePhoto] = []
    private(set) var drafts: [PhotoDraft] = []
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var isDeleting = false

    var error: String? {
        let messages = [remoteError, storageError].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    @ObservationIgnored private let storage: PhotoFileStorage
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var bundledPhotos: [String: WebsitePhoto] = [:]
    private var remoteError: String?
    private var storageError: String?
    private var canWriteDrafts = true
    private var hasRequestedRefresh = false

    /// Reads bundled photos and existing drafts immediately; performs no network request.
    init(bundle: Bundle = .main, directory: URL? = nil, session: URLSession = .shared) {
        let localDirectory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("Photos", isDirectory: true)
        self.directory = localDirectory
        self.storage = PhotoFileStorage(directory: localDirectory)
        self.session = session
        do {
            guard let url = bundle.url(forResource: "photo-library", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            photos = try WebsitePhoto.decode(Data(contentsOf: url), relativeTo: Self.siteURL)
            bundledPhotos = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        } catch {
            remoteError = "无法读取内置照片资料，请下拉刷新。\(error.localizedDescription)"
        }
        do {
            drafts = try PhotoFileStorage.readDrafts(in: localDirectory)
        } catch {
            canWriteDrafts = false
            storageError = "无法读取本地照片记录。为保留原有文件，已暂停导入和删除。\(error.localizedDescription)"
        }
    }

    func refreshIfNeeded() async {
        guard !hasRequestedRefresh else { return }
        hasRequestedRefresh = true
        await refresh()
    }

    /// A failed request leaves the bundled or last successful photo list visible.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await GitHubRepository(session: session).getRepositoryFile(path: "src/data/photo-library.json")
            photos = try WebsitePhoto.decode(data, relativeTo: Self.siteURL)
            remoteError = nil
        } catch is CancellationError {
            return
        } catch let failure as URLError where failure.code == .cancelled {
            return
        } catch {
            remoteError = photos.isEmpty
                ? "暂时无法连接网站，且没有可用照片。请稍后重试。\(error.localizedDescription)"
                : "暂时无法更新网站照片，正在显示内置或上次成功读取的资料。\(error.localizedDescription)"
        }
    }

    /// Imports at most ten selected images. Never uploads or publishes anything.
    @discardableResult
    func importPhotos(_ items: [PhotosPickerItem]) async -> PhotoImportResult {
        guard !items.isEmpty else { return PhotoImportResult(importedCount: 0, failedCount: 0, failures: []) }
        guard canWriteDrafts, !isImporting, !isDeleting else {
            return PhotoImportResult(importedCount: 0, failedCount: items.count, failures: ["本地照片暂时无法写入，请稍后重试。"])
        }
        isImporting = true
        defer { isImporting = false }
        var imported = 0
        var failures: [String] = []
        for (index, item) in items.prefix(10).enumerated() {
            do {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw CocoaError(.fileReadUnknown)
                }
                try Task.checkCancellation()
                let draft = try await storage.saveImage(data)
                let updated = ([draft] + drafts).sorted {
                    $0.importedAt == $1.importedAt ? $0.id.uuidString < $1.id.uuidString : $0.importedAt > $1.importedAt
                }
                do {
                    try await storage.writeMetadata(updated)
                } catch {
                    try? await storage.removeFiles(for: draft)
                    throw error
                }
                drafts = updated
                imported += 1
            } catch {
                failures.append("第 \(index + 1) 张：\(error.localizedDescription)")
            }
        }
        if items.count > 10 { failures.append("每次最多导入 10 张照片。") }
        return PhotoImportResult(importedCount: imported, failedCount: items.count - imported, failures: failures)
    }

    /// Persist the result before cleanup so reopening a retained draft cannot silently publish it twice.
    @discardableResult
    func recordPublication(id: UUID, commit: String?, uncertain: Bool = false) async -> Bool {
        guard canWriteDrafts, !isImporting, !isDeleting,
              let index = drafts.firstIndex(where: { $0.id == id }) else {
            storageError = "无法保存照片提交状态，请先查看 GitHub 提交记录，避免重复发布。"
            return false
        }
        isDeleting = true
        defer { isDeleting = false }
        var updated = drafts
        updated[index].publishedCommit = commit
        updated[index].publicationUncertain = uncertain
        do {
            try await storage.writeMetadata(updated)
            drafts = updated
            return true
        } catch {
            // Keep the result in memory even if persistence fails, and surface that limitation.
            drafts = updated
            storageError = "未能保存照片提交状态，请先查看 GitHub 提交记录，避免重复发布。\(error.localizedDescription)"
            return false
        }
    }

    /// Only accepts a local draft ID; published photos cannot be removed by this API.
    @discardableResult
    func removeDraft(id: UUID) async -> Bool {
        guard canWriteDrafts, !isImporting, !isDeleting,
              let draft = drafts.first(where: { $0.id == id }) else { return false }
        isDeleting = true
        defer { isDeleting = false }
        let updated = drafts.filter { $0.id != id }
        do {
            // Commit the manifest first so a failed write never loses a visible photo.
            try await storage.writeMetadata(updated)
            drafts = updated
            do {
                try await storage.removeFiles(for: draft)
                storageError = nil
            } catch {
                storageError = "照片已从本地列表移除，但清理图像文件失败。\(error.localizedDescription)"
            }
            return true
        } catch {
            storageError = "未能删除本地照片，原照片已保留。\(error.localizedDescription)"
            return false
        }
    }

    func bundledPreviewID(for photo: WebsitePhoto) -> String? {
        guard let bundled = bundledPhotos[photo.id], bundled.src == photo.src,
              bundled.preview == photo.preview, bundled.previewLarge == photo.previewLarge else { return nil }
        return photo.id
    }

    func fileURL(for draft: PhotoDraft, thumbnail: Bool = false) -> URL {
        directory.appendingPathComponent(thumbnail ? draft.thumbnailFilename : draft.filename)
    }

    private static let siteURL = URL(string: "https://mmddskq.top")!
    private static let libraryURL = URL(string: "https://raw.githubusercontent.com/skqfly/skqfly.github.io/main/src/data/photo-library.json")!
}
