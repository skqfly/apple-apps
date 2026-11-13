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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var status: ContentStatusFilter = ProcessInfo.processInfo.arguments.contains("--uitest-long-photo") ? .unpublished : .published
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var gallery: PhotoGallery?
    @State private var importMessage: String?
    @State private var showsImportResult = false
    @State private var isMovingDrafts = false
    @State private var draggingPhotoID: String?
    @State private var hoveredPhotoID: String?
    @State private var isSelecting = false
    @State private var selectedPhotoIDs: Set<String> = []
    @State private var photoFrames: [String: CGRect] = [:]
    @State private var swipedPhotoIDs: Set<String> = []

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
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .navigationTitle(isSelecting ? "已选择 “\(selectedPhotoIDs.count)”" : "图片")
        .navigationBarTitleDisplayMode(.large)
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
                photos: gallery.photos, drafts: gallery.drafts
            )
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                HStack {
                    Spacer()
                    batchBar
                    Spacer()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: isSelecting)
        .onChange(of: status) { _, _ in
            exitSelection()
        }
    }

    // MARK: - Navigation Bar Toolbar (Apple Native Photos / Files Style)

    @ToolbarContentBuilder
    private var topBarToolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") {
                    withAnimation(.snappy(duration: 0.22)) { exitSelection() }
                }
                .buttonStyle(AppleNavCapsuleButtonStyle())
                .accessibilityLabel("取消选择")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(selectedPhotoIDs.count == visiblePhotos.count ? "全部不选" : "全选") {
                    Haptics.selection()
                    withAnimation(.snappy(duration: 0.2)) {
                        if selectedPhotoIDs.count == visiblePhotos.count {
                            selectedPhotoIDs.removeAll()
                        } else {
                            selectedPhotoIDs = Set(visiblePhotos.map(\.id))
                        }
                    }
                }
                .buttonStyle(AppleNavCapsuleButtonStyle(isAccentText: true))
                .accessibilityLabel(selectedPhotoIDs.count == visiblePhotos.count ? "全部不选" : "全选")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    selectButton
                    addButton
                }
            }
        }
    }

    private var selectButton: some View {
        Button("选择") {
            withAnimation(.snappy(duration: 0.25)) { isSelecting = true }
            Haptics.medium()
        }
        .buttonStyle(AppleNavCapsuleButtonStyle())
        .accessibilityLabel("选择照片")
        .accessibilityIdentifier("photo-select-button")
    }

    private var addButton: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
            Image(systemName: "plus")
        }
        .buttonStyle(AppleNavCircleButtonStyle(size: 34, isAccent: true))
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
                }
                if status == .unpublished {
                    ForEach(store.drafts) { draft in
                        Button { open(.local(draft)) } label: {
                            photoTile { LocalPhotoImage(url: store.fileURL(for: draft, thumbnail: true), fallbackURL: store.fileURL(for: draft, thumbnail: false)) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("photo-draft-\(draft.id.uuidString)")
                        .accessibilityLabel(draft.title.isEmpty ? "未发表照片" : draft.title)
                        .accessibilityHint("在 App 内查看大图")
                    }
                }
            }
            .onPreferenceChange(PhotoFramePreferenceKey.self) { frames in
                photoFrames = frames
            }
            .gesture(
                isSelecting ? swipeSelectGesture : nil
            )
            .onDrop(of: [.text], delegate: PhotoReorderDrop(
                destinationID: nil, draggingID: $draggingPhotoID,
                hoveredID: $hoveredPhotoID, library: library
            ))
            .animation(.snappy(duration: 0.25), value: visiblePhotos.map(\.id))
        }
    }

    // Swipe to select gesture (Apple Photos official experience)
    private var swipeSelectGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let point = value.location
                for (id, frame) in photoFrames {
                    if frame.contains(point) && !swipedPhotoIDs.contains(id) {
                        swipedPhotoIDs.insert(id)
                        Haptics.selection()
                        withAnimation(.snappy(duration: 0.12)) {
                            if selectedPhotoIDs.contains(id) {
                                selectedPhotoIDs.remove(id)
                            } else {
                                selectedPhotoIDs.insert(id)
                            }
                        }
                    }
                }
            }
            .onEnded { _ in
                swipedPhotoIDs.removeAll()
            }
    }

    /// Bound both drawing and hit testing to the tile, including very tall images.
    private func photoTile<Content: View>(@ViewBuilder image: @escaping () -> Content) -> some View {
        Color.clear
            .aspectRatio(0.76, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    image()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .allowsHitTesting(false)
            }
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 16))
            .contentShape(.rect)
    }

    private func photoImage(_ photo: WebsitePhoto) -> some View {
        if let local = library.localPreviewURL(for: photo.id) {
            return AnyView(LocalPhotoImage(url: local))
        }
        if photo.preview.isFileURL {
            return AnyView(LocalPhotoImage(url: photo.preview))
        }
        return AnyView(RemotePhotoImage(url: photo.preview, allowsRetry: false, bundledPreviewID: store.bundledPreviewID(for: photo)))
    }

    @ViewBuilder
    private func photoCell(_ photo: WebsitePhoto) -> some View {
        if isSelecting {
            selectableCell(photo)
        } else {
            draggableCell(photo)
        }
    }

    // Official Apple Photos Style Checkmark Selection (Right-Bottom Checkmark, No Heavy Border)
    private func selectableCell(_ photo: WebsitePhoto) -> some View {
        let isSelected = selectedPhotoIDs.contains(photo.id)
        return Button {
            toggleSelection(photo)
        } label: {
            photoTile { photoImage(photo) }
                .scaleEffect(isSelected ? 0.95 : 1.0)
                .opacity(isSelected ? 0.92 : 1.0)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.appAccent)
                        .frame(width: 24, height: 24)
                        .overlay {
                            Circle().strokeBorder(Color.white, lineWidth: 1.6)
                        }
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.4)
                        .background(Circle().fill(Color.black.opacity(0.25)))
                        .frame(width: 24, height: 24)
                }
            }
            .padding(8)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .animation(.snappy(duration: 0.16), value: isSelected)
        .accessibilityLabel(photo.title)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityIdentifier("photo-tile-\(photo.id)")
    }

    private func draggableCell(_ photo: WebsitePhoto) -> some View {
        Button { open(.website(photo)) } label: {
            photoTile { photoImage(photo) }
        }
        .buttonStyle(CollectionPressStyle())
        .scaleEffect(draggingPhotoID == photo.id ? 1.03 : 1)
        .zIndex(draggingPhotoID == photo.id ? 1 : 0)
        .overlay {
            if hoveredPhotoID == photo.id && draggingPhotoID != photo.id {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.appAccent, lineWidth: 2.5)
            }
        }
        .animation(.snappy(duration: 0.20), value: draggingPhotoID == photo.id)
        .animation(.snappy(duration: 0.20), value: hoveredPhotoID == photo.id)
        .accessibilityLabel(photo.title)
        .accessibilityHint("在 App 内查看大图，长按后拖动可调整顺序")
        .accessibilityIdentifier("photo-tile-\(photo.id)")
        .onDrag {
            draggingPhotoID = photo.id
            Haptics.medium()
            return NSItemProvider(object: photo.id as NSString)
        } preview: {
            photoImage(photo)
                .frame(width: 160, height: 182)
                .clipped()
                .clipShape(.rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .onDrop(of: [.text], delegate: PhotoReorderDrop(
            destinationID: photo.id, draggingID: $draggingPhotoID,
            hoveredID: $hoveredPhotoID, library: library
        ))
    }

    // MARK: - Harmonized, Well-proportioned Floating Batch Bar (Balancing with Tab Bar)

    @ViewBuilder
    private var batchBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(selectedPhotoIDs.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            Spacer(minLength: 4)

            if status == .unpublished {
                Button {
                    publishSelected()
                } label: {
                    Text("发表")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedPhotoIDs.isEmpty ? Color.secondary : Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            selectedPhotoIDs.isEmpty ? Color.secondary.opacity(0.15) : Color.appAccent,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canPublish || selectedPhotoIDs.isEmpty)

                Button {
                    trashSelected()
                } label: {
                    Text("移到回收站")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selectedPhotoIDs.isEmpty ? Color.secondary : Color.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(selectedPhotoIDs.isEmpty ? 0.05 : 0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedPhotoIDs.isEmpty)
            } else {
                Button {
                    unpublishSelected()
                } label: {
                    Text("下架")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedPhotoIDs.isEmpty ? Color.secondary : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canPublish || selectedPhotoIDs.isEmpty)

                Button {
                    trashSelected()
                } label: {
                    Text("移到回收站")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selectedPhotoIDs.isEmpty ? Color.secondary : Color.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(selectedPhotoIDs.isEmpty ? 0.05 : 0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedPhotoIDs.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 320)
        .liquidGlassCapsule(interactive: true)
        .padding(.bottom, 12)
    }

    // MARK: - Selection & Batch Actions

    private func toggleSelection(_ photo: WebsitePhoto) {
        if selectedPhotoIDs.contains(photo.id) {
            selectedPhotoIDs.remove(photo.id)
            Haptics.selection()
        } else {
            selectedPhotoIDs.insert(photo.id)
            Haptics.selection()
        }
    }

    private func exitSelection() {
        isSelecting = false
        selectedPhotoIDs.removeAll()
        swipedPhotoIDs.removeAll()
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
