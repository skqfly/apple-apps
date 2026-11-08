import SwiftUI
import PhotosUI

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
        .toolbar { addToolbar }
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
    }

    @ToolbarContentBuilder
    private var addToolbar: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarTrailing) { addButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { addButton }
        }
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
                    Button { open(.website(photo)) } label: {
                        photoTile {
                            if photo.preview.isFileURL {
                                LocalPhotoImage(url: photo.preview)
                            } else {
                                RemotePhotoImage(url: photo.preview, allowsRetry: false, bundledPreviewID: store.bundledPreviewID(for: photo))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.title)
                    .accessibilityHint("在 App 内查看大图")
                }
                if status == .unpublished {
                    ForEach(store.drafts) { draft in
                        Button { open(.local(draft)) } label: {
                            photoTile { LocalPhotoImage(url: store.fileURL(for: draft, thumbnail: true)) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("photo-draft-\(draft.id.uuidString)")
                        .accessibilityLabel(draft.title.isEmpty ? "未发表照片" : draft.title)
                        .accessibilityHint("在 App 内查看大图")
                    }
                }
            }
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
