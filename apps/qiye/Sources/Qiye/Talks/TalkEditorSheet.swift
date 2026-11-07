import SwiftUI
import PhotosUI

@MainActor
struct TalkEditorSheet: View {
    let post: TalkPost?
    let library: ContentLibraryStore
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var date: Date
    @State private var kept: [TalkImage]
    @State private var added: [TalkImageDraft] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var busy = false
    @State private var error: String?
    @State private var discard = false
    private let initialText: String

    init(post: TalkPost?, library: ContentLibraryStore, onSaved: @escaping () -> Void) {
        self.post = post; self.library = library; self.onSaved = onSaved
        _content = State(initialValue: post?.description ?? "")
        _date = State(initialValue: post?.date ?? .now)
        _kept = State(initialValue: post?.images ?? [])
        initialText = post?.description ?? ""
    }

    private var remaining: Int { max(0, 9 - kept.count - added.count) }
    private var hasContent: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !kept.isEmpty || !added.isEmpty }
    private var dirty: Bool { content != initialText || kept != (post?.images ?? []) || !added.isEmpty || date != (post?.date ?? date) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TextEditor(text: $content)
                        .scrollContentBackground(.hidden).frame(minHeight: 190)
                        .overlay(alignment: .topLeading) { if content.isEmpty { Text("这一刻，想说点什么…").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) } }
                        .accessibilityLabel("说说正文")
                    imageGrid
                    HStack(spacing: 22) {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, remaining), matching: .images) { Label("相册", systemImage: "photo") }
                        Button { if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true } else { error = "这台设备没有可用相机。" } } label: { Label("拍照", systemImage: "camera") }
                        Button { showPhotos = true } label: { Label("照片墙", systemImage: "square.grid.2x2") }
                    }
                    .font(.subheadline).disabled(remaining == 0 || busy)
                    Divider()
                    DatePicker("日期", selection: $date, displayedComponents: .date).font(.subheadline)
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red) }
                    Text(post == nil ? "保存后位于未发表，可继续编辑或选择发表。" : "保存到本机；公开内容的更新会加入首页待推送。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color.appSurface)
            .navigationTitle(post == nil ? "写说说" : "编辑说说").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { if dirty { discard = true } else { dismiss() } }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(!hasContent || content.count > 50_000 || busy).fontWeight(.semibold) }
            }
            .interactiveDismissDisabled(dirty || busy)
            .confirmationDialog("放弃未保存的修改？", isPresented: $discard, titleVisibility: .visible) { Button("放弃修改", role: .destructive) { dismiss() } }
            .sheet(isPresented: $showPhotos) {
                SitePhotoPicker(photos: library.photos(in: .published) + library.photos(in: .unpublished), limit: remaining) { selected in
                    for image in selected where !kept.contains(where: { $0.src == image.src }) { kept.append(image) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    guard remaining > 0, let data = image.jpegData(compressionQuality: 0.9), let draft = TalkImageConverter.convert(data) else { return }
                    added.append(draft)
                }.ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    busy = true
                    defer { busy = false; pickerItems = [] }
                    for item in items {
                        guard remaining > 0 else { break }
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self), let draft = TalkImageConverter.convert(data) else { error = "有一张图片无法读取，请重新选择。"; continue }
                            added.append(draft)
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }

    private var imageGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            ForEach(Array(kept.enumerated()), id: \.offset) { index, image in
                removable {
                    Group {
                        if let url = image.url, url.isFileURL { LocalPhotoImage(url: url) }
                        else { AsyncImage(url: image.url) { phase in if let loaded = phase.image { loaded.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) } } }
                    }
                } remove: { kept.remove(at: index) }
            }
            ForEach(added) { image in
                removable { if let ui = UIImage(data: image.jpeg) { Image(uiImage: ui).resizable().scaledToFill() } } remove: { added.removeAll { $0.id == image.id } }
            }
        }
    }

    private func removable<Content: View>(@ViewBuilder image: () -> Content, remove: @escaping () -> Void) -> some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay { image().allowsHitTesting(false) }.clipped().clipShape(.rect(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Button(action: remove) { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6)).padding(5) }.buttonStyle(.plain).accessibilityLabel("移除图片")
            }
    }
    private func save() {
        do { try library.saveTalk(text: content.trimmingCharacters(in: .whitespacesAndNewlines), date: date, kept: kept, newImages: added.map { ($0.jpeg, $0.width, $0.height) }, editing: post); onSaved(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
