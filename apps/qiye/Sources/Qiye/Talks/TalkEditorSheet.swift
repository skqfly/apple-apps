import SwiftUI
import PhotosUI

/// Edits an already published talk. Changes are staged and pushed together from the home page.
@MainActor
struct TalkEditorSheet: View {
    let post: TalkPost
    let pending: PendingChangesStore
    let photos: PhotoLibraryStore
    let onStaged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var date: Date
    @State private var kept: [TalkImage]
    @State private var added: [TalkImageDraft] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var showsSitePhotos = false
    @State private var isStaging = false
    @State private var error: String?

    init(post: TalkPost, pending: PendingChangesStore, photos: PhotoLibraryStore, onStaged: @escaping () -> Void) {
        self.post = post
        self.pending = pending
        self.photos = photos
        self.onStaged = onStaged
        _content = State(initialValue: post.description)
        _date = State(initialValue: post.date)
        _kept = State(initialValue: post.images)
    }

    private var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && content.count <= 50_000 && !isStaging
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日期") { DatePicker("发布日期", selection: $date, displayedComponents: .date) }
                Section {
                    TextEditor(text: $content).frame(minHeight: 180).accessibilityLabel("说说正文")
                    Text("\(content.count) / 50,000 字").font(.caption)
                        .foregroundStyle(content.count > 50_000 ? Color.red : Color.secondary)
                } header: { Text("内容") }
                Section("图片") {
                    imageGrid
                    TalkImageSources(remaining: 6 - kept.count - added.count, pickerItems: $pickerItems) {
                        showsCamera = true
                    } onSitePhotos: { showsSitePhotos = true }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                Section { Text("编辑会暂存到首页，一键推送后更新网站。").font(.footnote).foregroundStyle(.secondary) }
            }
            .disabled(isStaging)
            .navigationTitle("编辑说说")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isStaging) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await stage() } } label: {
                        if isStaging { ProgressView() } else { Text("暂存").fontWeight(.semibold) }
                    }
                    .disabled(!canSubmit)
                }
            }
            .fullScreenCover(isPresented: $showsCamera) { camera }
            .sheet(isPresented: $showsSitePhotos) { sitePhotoPicker }
            .onChange(of: pickerItems) { _, items in importPicked(items) }
        }
    }

    private var camera: some View {
        CameraPicker { image in
            if let draft = TalkImageConverter.convert(image.jpegData(compressionQuality: 0.9) ?? Data()) { added.append(draft) }
        }
        .ignoresSafeArea()
    }

    private var sitePhotoPicker: some View {
        SitePhotoPicker(photos: photos.photos, limit: 6 - kept.count - added.count) { selected in
            kept.append(contentsOf: selected.filter { source in !kept.contains { $0.src == source.src } })
        }
    }

    @ViewBuilder
    private var imageGrid: some View {
        if kept.isEmpty && added.isEmpty {
            Text("还没有图片").font(.caption).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(kept, id: \.src) { image in
                    removable(url: image.url) { kept.removeAll { $0.src == image.src } }
                }
                ForEach(added) { draft in
                    removable(data: draft.jpeg) { added.removeAll { $0.id == draft.id } }
                }
            }
        }
    }

    private func removable(url: URL? = nil, data: Data? = nil, remove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Color.secondary.opacity(0.15) }
                    }
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(4)
        }
    }

    private func importPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if kept.count + added.count >= 6 { break }
                if let data = try? await item.loadTransferable(type: Data.self), let draft = TalkImageConverter.convert(data) {
                    added.append(draft)
                }
            }
            pickerItems = []
        }
    }

    private func stage() async {
        guard canSubmit else { return }
        isStaging = true
        error = nil
        do {
            try pending.stageTalkEdit(
                talkID: post.id,
                text: content.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                keptSources: kept.map(\.src),
                newImages: added.map { ($0.jpeg, $0.width, $0.height) }
            )
            onStaged()
            isStaging = false
            dismiss()
        } catch {
            isStaging = false
            self.error = error.localizedDescription
        }
    }
}

/// Shared image source buttons: system album, camera, and the site photo page.
struct TalkImageSources: View {
    let remaining: Int
    @Binding var pickerItems: [PhotosPickerItem]
    let onCamera: () -> Void
    let onSitePhotos: () -> Void

    var body: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, remaining), matching: .images) {
            Label("从相册选择", systemImage: "photo.on.rectangle")
        }
        .disabled(remaining <= 0)
        Button(action: onCamera) { Label("拍照", systemImage: "camera") }
            .disabled(remaining <= 0)
        Button(action: onSitePhotos) { Label("从照片页选择", systemImage: "rectangle.stack") }
            .disabled(remaining <= 0)
    }
}

/// Picks images that already exist on the site photo page, so a talk can reuse them.
struct SitePhotoPicker: View {
    let photos: [WebsitePhoto]
    let limit: Int
    let onSelect: ([TalkImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(photos) { photo in
                        Button { toggle(photo.id) } label: {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    AsyncImage(url: photo.preview) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                        else { Color.secondary.opacity(0.15) }
                                    }
                                }
                                .clipped()
                                .overlay(alignment: .topTrailing) {
                                    if selected.contains(photo.id) {
                                        Image(systemName: "checkmark.circle.fill").padding(6).foregroundStyle(.white, Color.appAccent)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("选择网站照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入 \(selected.count)") { confirm() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) }
        else if selected.count < limit { selected.insert(id) }
    }

    private func confirm() {
        let images = photos.filter { selected.contains($0.id) }.map {
            TalkImage(src: $0.sourcePath, width: $0.width, height: $0.height, alt: $0.alt, preview: $0.preview.path, previewLarge: $0.previewLarge.path)
        }
        onSelect(images)
        dismiss()
    }
}
