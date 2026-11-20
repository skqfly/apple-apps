import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct PhotosScreen: View {
    let store: PhotoLibraryStore
    let repository: GitHubRepository
    let pending: PendingChangesStore
    let library: ContentLibraryStore
    let canPublish: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var status: ContentStatusFilter = ProcessInfo.processInfo.arguments.contains("--uitest-long-photo") ? .unpublished : .published
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var gallery: PhotoGallery?
    @State private var scrollPhotoID: String?
    @State private var importMessage: String?
    @State private var showsImportResult = false
    @State private var isMovingDrafts = false
    @State private var draggingPhotoID: String?
    @State private var hoveredPhotoID: String?
    @State private var isSelecting = false
    @State private var selectedPhotoIDs: Set<String> = []
    @State private var photoFrames: [String: CGRect] = [:]
    @Namespace private var photoZoom

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 250 : 150), spacing: 12)]
    }

    private var visiblePhotos: [WebsitePhoto] { library.photos(in: status) }
    private var isBusy: Bool { store.isImporting || store.isDeleting || isMovingDrafts }
    private var usesFixture: Bool { ProcessInfo.processInfo.arguments.contains("--uitest-long-photo") }
    private var counts: [ContentStatusFilter: Int] {
        [
            .published: library.photos(in: .published).count,
            .unpublished: library.photos(in: .unpublished).count + store.drafts.count
        ]
    }

    private var selectedPhotos: [WebsitePhoto] {
        visiblePhotos.filter { selectedPhotoIDs.contains($0.id) }
    }
    private var canBatchPublish: Bool {
        canPublish
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !isSelecting {
                    ContentStatusPicker(
                        selection: $status,
                        categories: [.published, .unpublished],
                        counts: counts,
                        titleOverrides: [.unpublished: "已下架"]
                    )
                    .zIndex(1)
                }

                if let error = store.error {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if isBusy { ProgressView("正在保存照片…") }

                photoGrid
                    .coordinateSpace(name: "PhotoGridSpace")
            }
            .padding(.horizontal, AppPageLayout.horizontalInset)
            .padding(.top, AppPageLayout.topInset)
            .padding(.bottom, 24)
        }
        .scrollPosition(id: $scrollPhotoID, anchor: .center)
        .appPageBackground()
        .appNavigationTitle(isSelecting ? "已选 \(selectedPhotoIDs.count) 张" : "图片")
        .toolbar { topBarToolbar }
        .refreshable { await refresh() }
        .task {
            library.syncPhotos(store.photos, authoritative: store.hasRemoteSnapshot)
            await store.refreshIfNeeded()
            library.syncPhotos(store.photos, authoritative: store.hasRemoteSnapshot)
            let failures = await moveDraftsToLibrary()
            if !failures.isEmpty { report(failures.joined(separator: "\n")) }
        }
        .onChange(of: store.photos) { _, photos in library.syncPhotos(photos, authoritative: store.hasRemoteSnapshot) }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .alert("照片", isPresented: $showsImportResult) {
            Button("好", role: .cancel) { }
        } message: { Text(importMessage ?? "") }
        .fullScreenCover(item: $gallery) { gallery in
            PhotoDetailScreen(
                selection: gallery.selection, store: store, repository: repository, pending: pending,
                library: library, canPublish: canPublish,
                photos: gallery.photos, drafts: gallery.drafts, zoomNamespace: photoZoom,
                onPhotoChange: { id in
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { scrollPhotoID = id }
                }
            )
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                HStack {
                    Spacer()
                    batchBar
                    Spacer()
                }
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isSelecting)
        .onChange(of: status) { _, _ in
            exitSelection()
        }
    }

    // MARK: - Navigation Bar Actions

    @ToolbarContentBuilder
    private var topBarToolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { exitSelection() }
                } label: {
                    ToolbarActionIcon("取消选择", systemImage: "xmark")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                let allSelected = selectedPhotoIDs.count == visiblePhotos.count
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        if allSelected {
                            selectedPhotoIDs.removeAll()
                        } else {
                            selectedPhotoIDs = Set(visiblePhotos.map(\.id))
                        }
                    }
                } label: {
                    ToolbarActionIcon(
                        allSelected ? "全部不选" : "全选",
                        systemImage: allSelected ? "minus.square" : "checkmark.square"
                    )
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                selectButton
            }
            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                addButton
            }
        }
    }

    private var selectButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { isSelecting = true }
            Haptics.medium()
        } label: {
            ToolbarActionIcon("选择照片", systemImage: "checkmark")
        }
        .disabled(visiblePhotos.isEmpty || isBusy)
        .accessibilityLabel("选择照片")
        .accessibilityIdentifier("photo-select-button")
    }

    private var addButton: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
            ToolbarActionIcon("添加照片", systemImage: "plus")
        }
        .disabled(isBusy)
        .accessibilityLabel("添加照片")
        .accessibilityIdentifier("photo-add-button")
        .accessibilityHint("保存到未发表，预览后可发表")
    }

    // MARK: - Photo Grid with Swipe to Select

    @ViewBuilder
    private var photoGrid: some View {
        if store.isLoading && visiblePhotos.isEmpty && status == .published {
            ProgressView("正在读取网站照片…").frame(maxWidth: .infinity).padding(.vertical, 50)
        } else if visiblePhotos.isEmpty && (status != .unpublished || store.drafts.isEmpty) {
            ContentUnavailableView(
                "暂无\(status.title)照片", systemImage: status == .deleted ? "trash" : "photo.on.rectangle",
                description: Text(status == .deleted ? "删除的照片会保留在回收站中。" : "点右上角添加照片，或下拉刷新。")
            )
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visiblePhotos) { photo in
                    photoCell(photo)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: PhotoFramePreferenceKey.self,
                                        value: [photo.id: geo.frame(in: .named("PhotoGridSpace"))]
                                    )
                            }
                        )
                        .id(PhotoSelection.website(photo).id)
                }
                if status == .unpublished {
                    ForEach(store.drafts) { draft in
                        Button { open(.local(draft)) } label: {
                            photoTile { LocalPhotoImage(url: store.fileURL(for: draft, thumbnail: true), fallbackURL: store.fileURL(for: draft, thumbnail: false)) }
                                .collectionZoomSource(id: PhotoSelection.local(draft).id, namespace: photoZoom)
                        }
                        .buttonStyle(CollectionPressStyle())
                        .accessibilityIdentifier("photo-draft-\(draft.id.uuidString)")
                        .accessibilityLabel(draft.title.isEmpty ? "未发表照片" : draft.title)
                        .accessibilityHint("在 App 内查看大图")
                        .id(PhotoSelection.local(draft).id)
                    }
                }
            }
            .scrollTargetLayout()
            .onPreferenceChange(PhotoFramePreferenceKey.self) { frames in
                photoFrames = frames
            }
            .onDrop(of: [.text], delegate: PhotoReorderDrop(
                destinationID: nil, draggingID: $draggingPhotoID,
                hoveredID: $hoveredPhotoID, library: library
            ))
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: visiblePhotos.map(\.id))
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedPhotoIDs.contains(id) { selectedPhotoIDs.remove(id) }
        else { selectedPhotoIDs.insert(id) }
        Haptics.selection()
    }

    private func exitSelection() {
        isSelecting = false
        selectedPhotoIDs.removeAll()
        Haptics.light()
    }

    private func publishSelected() {
        applyBatch(to: .published) { try library.setPhotoState($0, to: .published) }
    }

    private func unpublishSelected() {
        applyBatch(to: .unpublished) { try library.setPhotoState($0, to: .unpublished) }
    }

    private func trashSelected() {
        let count = selectedPhotoIDs.count
        applyBatch(to: .deleted) { try library.setPhotoState($0, to: .deleted) }
        report("已将 \(count) 张照片移到个人中心回收站，网站变更会在首页推送后生效。")
    }

    private func applyBatch(to target: ContentStatusFilter, _ operation: (WebsitePhoto) throws -> Void) {
        let count = selectedPhotoIDs.count
        for photo in selectedPhotos {
            do { try operation(photo) }
            catch { report(error.localizedDescription); return }
        }
        exitSelection()
        if target != .deleted {
            report("已处理 \(count) 张照片（\(target == .unpublished ? "已下架" : target.title)）。网站变更会在首页推送后生效。")
        }
    }

    private func open(_ photo: PhotoSelection) {
        gallery = PhotoGallery(selection: photo, photos: visiblePhotos,
                               drafts: status == .unpublished ? store.drafts : [])
    }

    private func refresh() async {
        await store.refresh()
        library.syncPhotos(store.photos, authoritative: store.hasRemoteSnapshot)
    }

    private func report(_ message: String) {
        importMessage = message
        showsImportResult = true
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        let result = await store.importPhotos(items)
        pickerItems = []
        let failures = await moveDraftsToLibrary()
        if result.importedCount > 0 { status = .unpublished }
        report(([result.message] + failures).joined(separator: "\n"))
    }

    private func moveDraftsToLibrary() async -> [String] {
        guard !usesFixture, !isMovingDrafts else { return [] }
        isMovingDrafts = true
        defer { isMovingDrafts = false }
        var failures: [String] = []
        for draft in store.drafts {
            do {
                try await library.importPhoto(draft: draft, url: store.fileURL(for: draft))
                if !(await store.removeDraft(id: draft.id)) {
                    failures.append(store.error ?? "照片已存入内容库，本地导入记录尚未清理。")
                }
            } catch {
                failures.append("\(draft.title)：\(error.localizedDescription)")
            }
        }
        return failures
    }
}

// MARK: - PreferenceKey for Swipe to Select

private struct PhotoFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Reorders published photos while a drag is in flight.
private struct PhotoReorderDrop: DropDelegate {
    let destinationID: String?
    @Binding var draggingID: String?
    @Binding var hoveredID: String?
    let library: ContentLibraryStore

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != destinationID else { return }
        hoveredID = destinationID
        do {
            try library.movePhoto(draggingID, before: destinationID)
            Haptics.selection()
        } catch {
            self.draggingID = nil
            self.hoveredID = nil
        }
    }

    func dropExited(info: DropInfo) {
        if hoveredID == destinationID { hoveredID = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        hoveredID = nil
        Haptics.medium()
        return true
    }
}

/// Capture the selected item and its browsing context in one presentation value.
private struct PhotoGallery: Identifiable {
    let selection: PhotoSelection
    let photos: [WebsitePhoto]
    let drafts: [PhotoDraft]
    var id: String { selection.id }
}
