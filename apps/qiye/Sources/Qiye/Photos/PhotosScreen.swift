import SwiftUI
import PhotosUI

@MainActor
struct PhotosScreen: View {
    let store: PhotoLibraryStore
    let repository: GitHubRepository
    let canPublish: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsDrafts = ProcessInfo.processInfo.arguments.contains("--uitest-long-photo")
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selection: PhotoSelection?
    @State private var importMessage: String?
    @State private var showsImportResult = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 250 : 150), spacing: 8)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("照片范围", selection: $showsDrafts) {
                    Text("网站").tag(false)
                    Text("待发布 \(store.drafts.count)").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("photo-source-picker")
                .zIndex(1)
                if let error = store.error {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if store.isImporting { ProgressView("正在保存照片…") }
                if showsDrafts { localGrid } else { websiteGrid }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .navigationTitle("照片")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("添加照片", systemImage: "plus")
                }
                .disabled(store.isImporting || store.isDeleting)
                .accessibilityHint("选择照片，预览后可发布到 GitHub")
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.refreshIfNeeded() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let result = await store.importPhotos(items)
                pickerItems = []
                if result.importedCount > 0 { showsDrafts = true }
                importMessage = result.message
                showsImportResult = true
            }
        }
        .alert("照片已准备", isPresented: $showsImportResult) {
            Button("好", role: .cancel) { }
        } message: { Text(importMessage ?? "") }
        .fullScreenCover(item: $selection) { selected in
            PhotoDetailScreen(selection: selected, store: store, repository: repository, canPublish: canPublish)
        }
    }

    @ViewBuilder
    private var websiteGrid: some View {
        if store.isLoading && store.photos.isEmpty {
            ProgressView("正在读取网站照片…").frame(maxWidth: .infinity).padding(.vertical, 50)
        } else if store.photos.isEmpty && store.error == nil {
            ContentUnavailableView("暂无网站照片", systemImage: "photo.on.rectangle", description: Text("下拉刷新，或从左上角添加照片。"))
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.photos) { photo in
                    Button { selection = .website(photo) } label: {
                        photoTile {
                            RemotePhotoImage(url: photo.preview, allowsRetry: false, bundledPreviewID: store.bundledPreviewID(for: photo))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.title)
                    .accessibilityHint("查看照片大图")
                }
            }
        }
    }

    @ViewBuilder
    private var localGrid: some View {
        if store.drafts.isEmpty {
            ContentUnavailableView("还没有待发布照片", systemImage: "photo.badge.plus", description: Text("从左上角选取照片，再点开大图确认发布。"))
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.drafts) { draft in
                    Button { selection = .local(draft) } label: {
                        photoTile {
                            LocalPhotoImage(url: store.fileURL(for: draft, thumbnail: true))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("photo-draft-\(draft.id.uuidString)")
                    .accessibilityLabel("待发布照片")
                    .accessibilityHint("预览并发布到网站")
                }
            }
        }
    }

    /// The image is clipped twice so neither its pixels nor its hit area can escape the tile.
    private func photoTile<Content: View>(@ViewBuilder image: () -> Content) -> some View {
        Color.clear
            .aspectRatio(0.88, contentMode: .fit)
            .overlay {
                image()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .clipped()
            .contentShape(.rect)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 12))
    }
}
