import SwiftUI
import PhotosUI

@MainActor
struct NewTalkSheet: View {
    let pending: PendingChangesStore
    let onStaged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var date = Date.now
    @State private var images: [TalkImageDraft] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var isStaging = false
    @State private var error: String?

    private var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        content.count <= 50_000 && !isStaging
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日期") {
                    DatePicker("发布日期", selection: $date, displayedComponents: .date)
                }
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                        .accessibilityLabel("说说正文")
                    Text("支持 Markdown。\(content.count) / 50,000 字")
                        .font(.caption).foregroundStyle(content.count > 50_000 ? Color.red : Color.secondary)
                } header: { Text("内容") }
                Section("图片") {
                    imageGrid
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 6 - images.count, matching: .images) {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                    }
                    .disabled(images.count >= 6)
                    Button {
                        showsCamera = true
                    } label: {
                        Label("拍照", systemImage: "camera")
                    }
                    .disabled(images.count >= 6)
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.red)
                    }
                }
                Section {
                    Text("说说只有文字和图片，没有标题。暂存后到首页一键推送。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(isStaging)
            .navigationTitle("新的说说")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isStaging)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await stage() }
                    } label: {
                        if isStaging { ProgressView().accessibilityLabel("正在暂存") }
                        else { Text("暂存").fontWeight(.semibold) }
                    }
                    .disabled(!canSubmit)
                }
            }
            .interactiveDismissDisabled(isStaging || !content.isEmpty || !images.isEmpty)
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { image in
                    if let draft = TalkImageConverter.convert(image.jpegData(compressionQuality: 0.9) ?? Data()) {
                        images.append(draft)
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if images.count >= 6 { break }
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let draft = TalkImageConverter.convert(data) {
                            images.append(draft)
                        }
                    }
                    pickerItems = []
                }
            }
        }
    }

    @ViewBuilder
    private var imageGrid: some View {
        if images.isEmpty {
            Text("还没有图片").font(.caption).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(images) { draft in
                    ZStack(alignment: .topTrailing) {
                        if let ui = UIImage(data: draft.jpeg) {
                            Image(uiImage: ui)
                                .resizable().scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button {
                            images.removeAll { $0.id == draft.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .padding(4)
                    }
                }
            }
        }
    }

    private func stage() async {
        guard canSubmit else { return }
        isStaging = true
        error = nil
        do {
            try pending.stageTalk(
                text: content.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                images: images.map { ($0.jpeg, $0.width, $0.height) }
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
