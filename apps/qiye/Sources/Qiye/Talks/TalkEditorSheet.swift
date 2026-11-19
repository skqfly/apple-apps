import SwiftUI
import PhotosUI

@MainActor
struct TalkEditorSheet: View {
    let post: TalkPost?
    let library: ContentLibraryStore
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    GlassActionGroup {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, remaining), matching: .images) {
                            ActionIcon("相册", systemImage: "photo.on.rectangle.angled")
                        }

                        Button {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showCamera = true
                            } else {
                                error = "这台设备没有可用相机。"
                            }
                        } label: {
                            ActionIcon("拍照", systemImage: "camera")
                        }

                        Button {
                            showPhotos = true
                        } label: {
                            ActionIcon("照片墙", systemImage: "square.grid.2x2")
                        }
                    }
                    .buttonStyle(CollectionPressStyle())
                    .disabled(remaining == 0 || busy)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("发表状态")
                            .font(.subheadline.weight(.medium))
                            .accessibilityAddTraits(.isHeader)

                        ContentActionChoices {
                            stateButton("已发表", value: .published)
                            stateButton("未发表", value: .unpublished)
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
            .appPageBackground()
            .appNavigationTitle(post == nil ? "写说说" : "编辑说说")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if dirty { discard = true } else { dismiss() }
                    } label: {
                        ToolbarActionIcon("取消", systemImage: "xmark")
                    }
                    .disabled(busy)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        ToolbarActionIcon(
                            publishState == .published ? "发表" : "保存",
                            systemImage: publishState == .published ? "paperplane" : "checkmark"
                        )
                    }
                    .toolbarConfirmationStyle()
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
                    ActionIcon("移除图片", systemImage: "xmark")
                        .liquidGlassCircle()
                }
                .buttonStyle(CollectionPressStyle())
                .accessibilityLabel("移除图片")
            }
    }

    private func stateButton(_ title: String, value: ContentStatusFilter) -> some View {
        let isSelected = publishState == value
        return Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                publishState = value
            }
        } label: {
            Label(title, systemImage: isSelected ? "checkmark" : "circle")
        }
        .contentActionStyle(isSelected ? .prominent : .standard)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
