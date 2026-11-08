import SwiftUI

@MainActor
struct PhotoDetailScreen: View {
    let selection: PhotoSelection
    let store: PhotoLibraryStore
    let repository: GitHubRepository
    let pending: PendingChangesStore
    let library: ContentLibraryStore
    let canPublish: Bool
    var photos: [WebsitePhoto] = []
    var drafts: [PhotoDraft] = []
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int?
    @State private var deleteTarget: WebsitePhoto?
    @State private var purgeTarget: WebsitePhoto?
    @State private var confirmsDelete = false
    @State private var confirmsPurge = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var showsMessage = false
    @State private var dismissesAfterMessage = false

    private var selections: [PhotoSelection] {
        let values = photos.map(PhotoSelection.website) + drafts.map(PhotoSelection.local)
        return values.isEmpty ? [selection] : values
    }

    private var initialIndex: Int { selections.firstIndex { $0.id == selection.id } ?? 0 }
    private var current: PhotoSelection {
        let index = currentIndex ?? initialIndex
        return selections.indices.contains(index) ? selections[index] : selection
    }

    private var items: [MediaViewerItem] {
        selections.map { selected in
            switch selected {
            case .website(let photo):
                MediaViewerItem(id: selected.id, url: photo.src, previewURL: photo.previewLarge)
            case .local(let draft):
                MediaViewerItem(id: selected.id, url: store.fileURL(for: draft), previewURL: store.fileURL(for: draft, thumbnail: true))
            }
        }
    }

    var body: some View {
        MediaViewer(
            items: items, initialIndex: initialIndex,
            actions: AnyView(managementMenu),
            onIndexChange: { currentIndex = $0 }
        )
        .accessibilityIdentifier("photo-detail-screen")
        .confirmationDialog("移到已删除？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("移到已删除", role: .destructive) { moveToTrash() }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("照片将保留在已删除中，可恢复到未发表。网站变更会在首页推送后生效。")
        }
        .confirmationDialog("彻底删除这张照片？", isPresented: $confirmsPurge, titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) { purge() }
            Button("取消", role: .cancel) { purgeTarget = nil }
        } message: {
            Text("此操作无法撤销，照片将从内容库永久移除。")
        }
        .alert("操作状态", isPresented: $showsMessage) {
            Button("好", role: .cancel) {
                if dismissesAfterMessage { dismiss() }
            }
        } message: { Text(message ?? "") }
        .interactiveDismissDisabled(isWorking)
    }

    private var managementMenu: some View {
        Menu {
            switch current {
            case .website(let photo):
                let state = library.stateOfPhoto(photo.id)
                Section(state.title) {
                    if state == .deleted {
                        Button("恢复到未发表", systemImage: "arrow.uturn.backward") { restore(photo) }
                        Button("彻底删除", systemImage: "trash.slash", role: .destructive) {
                            purgeTarget = photo
                            confirmsPurge = true
                        }
                    } else {
                        if state == .published {
                            Button("下架到未发表", systemImage: "arrow.down.circle") { setState(photo, to: .unpublished) }
                                .disabled(!canPublish)
                        } else {
                            Button("发表", systemImage: "arrow.up.circle") { setState(photo, to: .published) }
                                .disabled(!canPublish)
                        }
                        Button("移到已删除", systemImage: "trash", role: .destructive) {
                            deleteTarget = photo
                            confirmsDelete = true
                        }
                        .disabled(state == .published && !canPublish)
                    }
                }
                if !canPublish && state != .deleted {
                    Text("登录 GitHub 后可发表与下架")
                }
            case .local(let draft):
                Button("保存到未发表", systemImage: "tray.and.arrow.down") {
                    Task { await importDraft(draft) }
                }
                .disabled(ProcessInfo.processInfo.arguments.contains("--uitest-long-photo"))
            }
        } label: {
            ZStack {
                Color.clear
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .disabled(isWorking)
        .accessibilityLabel("管理照片")
    }

    private func report(_ text: String) {
        message = text
        showsMessage = true
    }

    private func setState(_ photo: WebsitePhoto, to state: ContentStatusFilter) {
        do {
            try library.setPhotoState(photo, to: state)
            report("照片已设为\(state.title)。网站变更会在首页推送后生效。")
        } catch { report(error.localizedDescription) }
    }

    private func moveToTrash() {
        guard let photo = deleteTarget else { return }
        defer { deleteTarget = nil }
        do {
            try library.setPhotoState(photo, to: .deleted)
            report("已移到已删除，可随时恢复到未发表。网站变更会在首页推送后生效。")
        } catch { report(error.localizedDescription) }
    }

    private func restore(_ photo: WebsitePhoto) {
        do {
            try library.restorePhoto(photo)
            report("已恢复到未发表。")
        } catch { report(error.localizedDescription) }
    }

    private func purge() {
        guard let photo = purgeTarget else { return }
        defer { purgeTarget = nil }
        do {
            try library.purgePhoto(photo)
            dismissesAfterMessage = true
            report("照片已彻底删除。网站变更会在首页推送后生效。")
        } catch { report(error.localizedDescription) }
    }

    private func importDraft(_ draft: PhotoDraft) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await library.importPhoto(draft: draft, url: store.fileURL(for: draft))
            if await store.removeDraft(id: draft.id) { dismiss() }
            else { report(store.error ?? "已存入未发表，本地导入记录尚未清理。") }
        } catch { report(error.localizedDescription) }
    }
}
