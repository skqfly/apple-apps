import SwiftUI

@MainActor
struct DirectoryEditor: View {
    let store: SiteDirectoryStore
    let kind: DirectoryKind
    let original: SiteDirectoryEntry?
    let onSaved: (SiteDirectoryEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var url: String
    @State private var image: String
    @State private var tags: String
    @State private var categories: String
    @State private var saving = false
    @State private var error: String?

    init(store: SiteDirectoryStore, kind: DirectoryKind, original: SiteDirectoryEntry? = nil,
         onSaved: @escaping (SiteDirectoryEntry) -> Void = { _ in }) {
        self.store = store
        self.kind = kind
        self.original = original
        self.onSaved = onSaved
        _title = State(initialValue: original?.title ?? "")
        _description = State(initialValue: original?.description ?? "")
        _url = State(initialValue: original?.url ?? "")
        _image = State(initialValue: original?.image ?? "")
        _tags = State(initialValue: original?.tags?.joined(separator: ", ") ?? "")
        _categories = State(initialValue: original?.categories?.joined(separator: ", ") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $title)
                    TextField("网站或项目链接", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("简介", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                    TextField(kind == .friends ? "头像地址（可选）" : "封面地址（可选）", text: $image)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if kind == .projects {
                    Section {
                        TextField("分类", text: $categories)
                        TextField("标签", text: $tags)
                    } footer: {
                        Text("用逗号分隔多个分类或标签。")
                    }
                }
                Section {
                    Button("保存并提交到 GitHub") { Task { await save() } }
                        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if saving { ProgressView("正在提交…") }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text("提交后，网站将在 GitHub Pages 完成部署时更新。")
                }
            }
            .tint(.indigo)
            .navigationTitle((original == nil ? "添加" : "编辑") + kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { ActionIcon("关闭", systemImage: "xmark") }
                        .disabled(saving)
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        error = nil
        defer { saving = false }

        let draft = SiteDirectoryEntry(title: title, description: description, url: url, image: image,
                                       tags: items(tags), categories: items(categories), domain: nil)
        do {
            let saved = try await store.save(draft, kind: kind, replacing: original)
            Haptics.success()
            onSaved(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func items(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
