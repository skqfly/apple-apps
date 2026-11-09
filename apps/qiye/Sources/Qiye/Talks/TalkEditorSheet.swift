import SwiftUI
import PhotosUI

@MainActor
struct TalkEditorSheet: View {
    let post: TalkPost?
    let library: ContentLibraryStore
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var content: String
    @State private var date: Date
    @State private var publishState: ContentStatusFilter
    @State private var kept: [TalkImage]
    @State private var added: [TalkImageDraft] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var busy = false
    @State private var error: String?
    @State private var discard = false
    private let initialText: String
    private let initialPostState: ContentStatusFilter

    init(post: TalkPost?, library: ContentLibraryStore, onSaved: @escaping () -> Void) {
        self.post = post
        self.library = library
        self.onSaved = onSaved
        let existingState = post.map { library.stateOfTalk($0.id) } ?? .published
        _content = State(initialValue: post?.description ?? "")
        _date = State(initialValue: post?.date ?? .now)
        _publishState = State(initialValue: existingState == .deleted ? .unpublished : existingState)
        _kept = State(initialValue: post?.images ?? [])
        initialText = post?.description ?? ""
        initialPostState = existingState
    }

    private var remaining: Int { max(0, 9 - kept.count - added.count) }
    private var hasContent: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !kept.isEmpty || !added.isEmpty }
    private var dirty: Bool {
        content != initialText ||
        kept != (post?.images ?? []) ||
        !added.isEmpty ||
        date != (post?.date ?? date) ||
        publishState != initialPostState
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextEditor(text: $content)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
                        .overlay(alignment: .topLeading) {
                            if content.isEmpty {
                                Text("这一刻，想说点什么…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel("说说正文")

                    imageGrid

                    // Media toolbar
                    HStack(spacing: 20) {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, remaining), matching: .images) {
                            Label("相册", systemImage: "photo.on.rectangle.angled")
                        }

                        Button {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showCamera = true
                            } else {
                                error = "这台设备没有可用相机。"
                            }
                        } label: {
                            Label("拍照", systemImage: "camera")
                        }

                        Button {
                            showPhotos = true
                        } label: {
                            Label("照片墙", systemImage: "square.grid.2x2")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appAccent)
                    .disabled(remaining == 0 || busy)

                    Divider()

                    // Publishing State Picker
                    HStack {
                        Text("状态")
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                Haptics.selection()
                                withAnimation(.snappy(duration: 0.18)) {
                                    publishState = .published
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(publishState == .published ? Color(red: 0.16, green: 0.65, blue: 0.45) : Color.secondary.opacity(0.5))
                                        .frame(width: 6, height: 6)
                                    Text("已发表")
                                }
                                .font(.caption.weight(publishState == .published ? .semibold : .regular))
                                .foregroundStyle(publishState == .published ? Color.primary : Color.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    publishState == .published ? Color.appAccent.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color.secondary.opacity(0.08),
                                    in: Capsule()
                                )
                                .overlay {
                                    if publishState == .published {
                                        Capsule().strokeBorder(Color.appAccent.opacity(0.4), lineWidth: 0.8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                Haptics.selection()
                                withAnimation(.snappy(duration: 0.18)) {
                                    publishState = .unpublished
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(publishState == .unpublished ? Color.orange : Color.secondary.opacity(0.5))
                                        .frame(width: 6, height: 6)
                                    Text("未发表")
                                }
                                .font(.caption.weight(publishState == .unpublished ? .semibold : .regular))
                                .foregroundStyle(publishState == .unpublished ? Color.primary : Color.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    publishState == .unpublished ? Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color.secondary.opacity(0.08),
                                    in: Capsule()
                                )
                                .overlay {
                                    if publishState == .unpublished {
                                        Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Date Picker
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .font(.subheadline)

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Explanatory prompt
                    Text(publishState == .published
                        ? "选择「已发表」将加入首页待推送队列，推送后即刻同步至线上网站。"
                        : "选择「未发表」将作为草稿仅保留在本机，随时可修改或转为发表。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(post == nil ? "写说说" : "编辑说说")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if dirty { discard = true } else { dismiss() }
                    }
                    .disabled(busy)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(publishState == .published ? "发表" : "保存") {
                        save()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appAccent)
                    .disabled(!hasContent || content.count > 50_000 || busy)
                }
            }
            .interactiveDismissDisabled(dirty || busy)
            .confirmationDialog("放弃未保存的修改？", isPresented: $discard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $showPhotos) {
                SitePhotoPicker(photos: library.photos(in: .published) + library.photos(in: .unpublished), limit: remaining) { selected in
                    for image in selected where !kept.contains(where: { $0.src == image.src }) {
                        kept.append(image)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    guard remaining > 0, let data = image.jpegData(compressionQuality: 0.9),
                          let draft = TalkImageConverter.convert(data) else { return }
                    added.append(draft)
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    busy = true
                    defer { busy = false; pickerItems = [] }
                    for item in items {
                        guard remaining > 0 else { break }
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self),
                                  let draft = TalkImageConverter.convert(data) else {
                                error = "有一张图片无法读取，请重新选择。"
                                continue
                            }
                            added.append(draft)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private var imageGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(kept.enumerated()), id: \.offset) { index, image in
                removable {
                    Group {
                        if let url = image.url, url.isFileURL {
                            LocalPhotoImage(url: url)
                        } else {
                            AsyncImage(url: image.url) { phase in
                                if let loaded = phase.image {
                                    loaded.resizable().scaledToFill()
                                } else {
                                    Color.secondary.opacity(0.12)
                                }
                            }
                        }
                    }
                } remove: {
                    kept.remove(at: index)
                }
            }

            ForEach(added) { image in
                removable {
                    if let ui = UIImage(data: image.jpeg) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    }
                } remove: {
                    added.removeAll { $0.id == image.id }
                }
            }
        }
    }

    private func removable<Content: View>(@ViewBuilder image: () -> Content, remove: @escaping () -> Void) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { image().allowsHitTesting(false) }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.65))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除图片")
            }
    }

    private func save() {
        Haptics.medium()
        do {
            try library.saveTalk(
                text: content.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                kept: kept,
                newImages: added.map { ($0.jpeg, $0.width, $0.height) },
                editing: post,
                targetState: publishState
            )
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
