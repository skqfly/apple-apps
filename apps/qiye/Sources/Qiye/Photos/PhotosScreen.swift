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
    @State private var status: ContentStatusFilter = ProcessInfo.processInfo.arguments.contains("--uitest-long-photo") ? .unpublished : .published
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selection: PhotoSelection?
    @State private var viewingPhotos: [WebsitePhoto] = []
    @State private var viewingDrafts: [PhotoDraft] = []
    @State private var importMessage: String?
    @State private var showsImportResult = false
    @State private var isMovingDrafts = false
    @State private var draggingPhotoID: String?
    @State private var hoveredPhotoID: String?
    @State private var isSelecting = false
    @State private var selectedPhotoIDs: Set<String> = []
    @State private var confirmsBatchPurge = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 250 : 150), spacing: 8)]
    }

    private var visiblePhotos: [WebsitePhoto] { library.photos(in: status) }
    private var isBusy: Bool { store.isImporting || store.isDeleting || isMovingDrafts }
    private var usesFixture: Bool { ProcessInfo.processInfo.arguments.contains("--uitest-long-photo") }
    private var counts: [ContentStatusFilter: Int] {
        Dictionary(uniqueKeysWithValues: ContentStatusFilter.allCases.map { state in
            (state, library.photos(in: state).count + (state == .unpublished ? store.drafts.count : 0))
        })
    }

    private var selectedPhotos: [WebsitePhoto] {
        visiblePhotos.filter { selectedPhotoIDs.contains($0.id) }
    }
    private var canBatchPublish: Bool {
        canPublish && (status == .published || status == .unpublished)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentStatusPicker(selection: $status, counts: counts)
                    .accessibilityIdentifier("photo-source-picker")
                    .zIndex(1)
                if let error = store.error {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if isBusy { ProgressView("正在保存照片…") }
                photoGrid
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .navigationTitle("照片")
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
        .fullScreenCover(item: $selection) { selected in
            PhotoDetailScreen(
                selection: selected, store: store, repository: repository, pending: pending,
                library: library, canPublish: canPublish,
                photos: viewingPhotos, drafts: viewingDrafts
            )
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { batchBar }
        }
        .onChange(of: status) { _, _ in
            exitSelection()
        }
        .confirmationDialog("彻底删除选中的照片？", isPresented: $confirmsBatchPurge, titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) { purgeSelected() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("已选 \(selectedPhotoIDs.count) 张，此操作无法撤销。")
        }
    }

    @ToolbarContentBuilder
    private var topBarToolbar: some ToolbarContent {
        if isSelecting {
            if #available(iOS 26, *) {
                ToolbarItem(placement: .topBarTrailing) { cancelButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { cancelButton }
            }
        } else {
            if #available(iOS 26, *) {
                ToolbarItem(placement: .topBarTrailing) { HStack(spacing: 4) { selectButton; addButton } }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { HStack(spacing: 4) { selectButton; addButton } }
            }
        }
    }

    private var selectButton: some View {
        Button {
            isSelecting = true
            Haptics.medium()
        } label: {
            Text("选择")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.appAccent)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择照片")
    }

    private var cancelButton: some View {
        Button {
            exitSelection()
        } label: {
            Text("取消").font(.subheadline.weight(.semibold)).foregroundStyle(Color.appAccent)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("取消选择")
    }

    private var addButton: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.appAccent)
                .frame(width: 44, height: 44)
                .modifier(PhotoAddButtonBackground())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("添加照片")
        .accessibilityIdentifier("photo-add-button")
        .accessibilityHint("保存到未发表，预览后可发表")
    }

    @ViewBuilder
    private var photoGrid: some View {
        if store.isLoading && visiblePhotos.isEmpty && status == .published {
            ProgressView("正在读取网站照片…").frame(maxWidth: .infinity).padding(.vertical, 50)
        } else if visiblePhotos.isEmpty && (status != .unpublished || store.drafts.isEmpty) {
            ContentUnavailableView(
                "暂无\(status.title)照片", systemImage: status == .deleted ? "trash" : "photo.on.rectangle",
                description: Text(status == .deleted ? "删除的照片会保留在这里，可恢复到未发表。" : "点右上角添加照片，或下拉刷新。")
            )
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visiblePhotos) { photo in
                    photoCell(photo)
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
            .onDrop(of: [.text], delegate: PhotoReorderDrop(
                destinationID: nil, draggingID: $draggingPhotoID,
                hoveredID: $hoveredPhotoID, library: library
            ))
            .animation(.snappy(duration: 0.25), value: visiblePhotos.map(\.id))
        }
    }

    /// Bound both drawing and hit testing to the tile, including very tall images.
    private func photoTile<Content: View>(@ViewBuilder image: @escaping () -> Content) -> some View {
        Color.clear
            .aspectRatio(0.88, contentMode: .fit)
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
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
    }

    private func photoImage(_ photo: WebsitePhoto) -> some View {
        if photo.preview.isFileURL {
            return AnyView(LocalPhotoImage(url: photo.preview))
        } else {
            return AnyView(RemotePhotoImage(url: photo.preview, allowsRetry: false, bundledPreviewID: store.bundledPreviewID(for: photo)))
        }
    }

    @ViewBuilder
    private func photoCell(_ photo: WebsitePhoto) -> some View {
        if isSelecting {
            selectableCell(photo)
        } else {
            draggableCell(photo)
        }
    }

    private func selectableCell(_ photo: WebsitePhoto) -> some View {
        Button {
            toggleSelection(photo)
        } label: {
            photoTile { photoImage(photo) }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if selectedPhotoIDs.contains(photo.id) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.appAccent)
                    .padding(6)
            }
        }
        .overlay {
            if selectedPhotoIDs.contains(photo.id) {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.appAccent, lineWidth: 2.5)
            }
        }
        .animation(.snappy(duration: 0.15), value: selectedPhotoIDs.contains(photo.id))
        .accessibilityLabel(photo.title)
        .accessibilityValue(selectedPhotoIDs.contains(photo.id) ? "已选择" : "未选择")
        .accessibilityIdentifier("photo-tile-\(photo.id)")
    }

    private func draggableCell(_ photo: WebsitePhoto) -> some View {
        Button { open(.website(photo)) } label: {
            photoTile { photoImage(photo) }
        }
        .buttonStyle(.plain)
        .opacity(draggingPhotoID == photo.id ? 0 : 1)
        .overlay {
            if hoveredPhotoID == photo.id && draggingPhotoID != photo.id {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.appAccent, lineWidth: 2.5)
            }
        }
        .animation(.snappy(duration: 0.18), value: draggingPhotoID == photo.id)
        .animation(.snappy(duration: 0.18), value: hoveredPhotoID == photo.id)
        .accessibilityLabel(photo.title)
        .accessibilityHint("在 App 内查看大图，长按后拖动可调整顺序")
        .accessibilityIdentifier("photo-tile-\(photo.id)")
        .onDrag {
            draggingPhotoID = photo.id
            Haptics.medium()
            return NSItemProvider(object: photo.id as NSString)
        } preview: {
            photoTile { photoImage(photo) }
                .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
        }
        .onDrop(of: [.text], delegate: PhotoReorderDrop(
            destinationID: photo.id, draggingID: $draggingPhotoID,
            hoveredID: $hoveredPhotoID, library: library
        ))
    }

    @ViewBuilder
    private var batchBar: some View {
        HStack(spacing: 10) {
            Text("已选 \(selectedPhotoIDs.count) 张")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            switch status {
            case .unpublished:
                Button("发表") { publishSelected() }.disabled(!canPublish)
                Button("移到已删除") { trashSelected() }
            case .published:
                Button("下架") { unpublishSelected() }.disabled(!canPublish)
                Button("移到已删除") { trashSelected() }
            case .deleted:
                Button("恢复") { restoreSelected() }
                Button("彻底删除", role: .destructive) { confirmsBatchPurge = true }
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Selection & batch actions

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
        Haptics.light()
    }

    private func publishSelected() {
        applyBatch(to: .published) { library.setPhotoState($0, to: .published) }
    }

    private func unpublishSelected() {
        applyBatch(to: .unpublished) { library.setPhotoState($0, to: .unpublished) }
    }

    private func trashSelected() {
        applyBatch(to: .deleted) { library.setPhotoState($0, to: .deleted) }
    }

    private func restoreSelected() {
        applyBatch(to: .unpublished) { library.restorePhoto($0) }
    }

    private func purgeSelected() {
        let count = selectedPhotoIDs.count
        for photo in selectedPhotos {
            try? library.purgePhoto(photo)
        }
        exitSelection()
        report("已彻底删除 \(count) 张照片。")
    }

    private func applyBatch(to target: ContentStatusFilter, _ operation: (WebsitePhoto) throws -> Void) {
        let count = selectedPhotoIDs.count
        for photo in selectedPhotos {
            do { try operation(photo) }
            catch { report(error.localizedDescription); return }
        }
        exitSelection()
        report("已处理 \(count) 张照片（\(target.title)）。网站变更会在首页推送后生效。")
    }

    private func open(_ photo: PhotoSelection) {
        viewingPhotos = visiblePhotos
        viewingDrafts = status == .unpublished ? store.drafts : []
        selection = photo
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

private struct PhotoAddButtonBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: .circle)
                .overlay { Circle().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6) }
        }
    }
}

private enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

/// Reorders published photos while a drag is in flight. `movePhoto` writes both the
/// local wall order and the staged website order in one atomic transaction.
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
