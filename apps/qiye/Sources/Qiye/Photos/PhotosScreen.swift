import SwiftUI
import PhotosUI

/// The parent supplies its NavigationStack and may add a trailing profile toolbar item.
@MainActor
struct PhotosScreen: View {
    let store: PhotoLibraryStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsLocalOnly = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selection: PhotoSelection?
    @State private var importResult: PhotoImportResult?
    @State private var showsImportResult = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 250 : 150), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Picker("照片范围", selection: $showsLocalOnly) {
                    Text("全部").tag(false)
                    Text("本地").tag(true)
                }
                .pickerStyle(.segmented)

                if let error = store.error {
                    errorNotice(error)
                }
                if store.isImporting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在保存所选照片…").font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                }

                photoSections
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("照片")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("导入照片", systemImage: "plus")
                }
                .disabled(store.isImporting || store.isDeleting)
                .accessibilityHint("从系统相册选择最多十张照片，仅保存在本机")
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.refreshIfNeeded() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                importResult = await store.importPhotos(items)
                pickerItems = []
                if (importResult?.importedCount ?? 0) > 0 { showsLocalOnly = true }
                showsImportResult = true
            }
        }
        .alert("导入结果", isPresented: $showsImportResult) {
            Button("好", role: .cancel) { }
        } message: {
            Text(importResult?.message ?? "")
        }
        .fullScreenCover(item: $selection) { selected in
            PhotoDetailScreen(selection: selected, store: store)
        }
    }

    @ViewBuilder
    private var photoSections: some View {
        if showsLocalOnly {
            localSection
        } else {
            if !store.drafts.isEmpty { localSection }
            websiteSection
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("光影与日常").font(.title2.bold())
            Text("网站 \(store.photos.count) 张 · 本地 \(store.drafts.count) 张")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("导入的照片仅保存在本机。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var websiteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("网站照片", systemImage: "globe").font(.headline)
                Spacer()
                if store.isLoading {
                    ProgressView().accessibilityLabel("正在更新网站照片")
                }
            }
            .accessibilityAddTraits(.isHeader)
            if store.photos.isEmpty {
                if store.isLoading {
                    ProgressView("正在读取照片…")
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    ContentUnavailableView("暂无网站照片", systemImage: "photo.on.rectangle.angled", description: Text("下拉刷新，获取网站最新照片。"))
                }
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.photos) { photo in
                        Button {
                            selection = .website(photo)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Color.clear
                                    .frame(height: 180)
                                    .overlay {
                                        GeometryReader { geometry in
                                            RemotePhotoImage(url: photo.preview, allowsRetry: false, bundledPreviewID: photo.id, prefersBundledPreview: true)
                                                .frame(width: geometry.size.width, height: geometry.size.height)
                                        }
                                    }
                                    .clipped()
                                    .background(.quaternary)
                                    .clipShape(.rect(cornerRadius: 12))
                                Text(photo.title)
                                    .font(.subheadline).foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(photo.title)
                        .accessibilityHint("查看网站照片大图")
                    }
                }
            }
        }
    }

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("本地照片", systemImage: "iphone")
                .font(.headline).accessibilityAddTraits(.isHeader)
            if store.drafts.isEmpty {
                ContentUnavailableView {
                    Label("还没有本地照片", systemImage: "photo.badge.plus")
                } description: {
                    Text("轻点左上角加号，从系统相册导入。照片会保留在本机，不会上传到网站。")
                }
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.drafts) { draft in
                        Button {
                            selection = .local(draft)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Color.clear
                                    .frame(height: 180)
                                    .overlay {
                                        GeometryReader { geometry in
                                            LocalPhotoImage(url: store.fileURL(for: draft, thumbnail: true))
                                                .frame(width: geometry.size.width, height: geometry.size.height)
                                        }
                                    }
                                    .clipped()
                                    .background(.quaternary)
                                    .clipShape(.rect(cornerRadius: 12))
                                Text(draft.title).font(.subheadline).foregroundStyle(.primary)
                                Text(draft.importedAt, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(draft.title)，仅保存在本机，\(draft.importedAt.formatted(date: .abbreviated, time: .shortened))导入")
                        .accessibilityHint("查看本地照片大图，可在详情中删除")
                    }
                }
            }
        }
    }

    private func errorNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("部分内容暂时不可用", systemImage: "exclamationmark.triangle")
                .font(.subheadline.bold())
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Button("重新获取网站照片", systemImage: "arrow.clockwise") {
                Task { await store.refresh() }
            }
            .font(.subheadline)
            .disabled(store.isLoading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
