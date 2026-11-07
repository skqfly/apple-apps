import SwiftUI

@MainActor
struct NewTalkSheet: View {
    let repository: GitHubRepository
    let onPublished: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var date = Date.now
    @State private var isPublishing = false
    @State private var error: String?

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title.count <= 200 && content.count <= 50_000 && !isPublishing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("给这一刻起个名字", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.sentences)
                    if title.count > 200 {
                        Text("标题最多 200 字").font(.caption).foregroundStyle(.red)
                    }
                }
                Section("日期") {
                    DatePicker("发布日期", selection: $date, displayedComponents: .date)
                }
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 220)
                        .accessibilityLabel("说说正文")
                    Text("支持 Markdown。\(content.count) / 50,000 字")
                        .font(.caption).foregroundStyle(content.count > 50_000 ? Color.red : Color.secondary)
                } header: { Text("正文") }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.red)
                    }
                }
                Section {
                    Text("发布后会创建 GitHub 提交。网站更新以部署结果为准。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(isPublishing)
            .navigationTitle("新的说说")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await publish() } } label: {
                        if isPublishing { ProgressView().accessibilityLabel("正在发布") }
                        else { Text("发布").fontWeight(.semibold) }
                    }
                    .disabled(!canSubmit)
                }
            }
            .interactiveDismissDisabled(isPublishing || !title.isEmpty || !content.isEmpty)
        }
    }

    private func publish() async {
        guard canSubmit else { return }
        isPublishing = true
        error = nil
        do {
            let sha = try await repository.addTalk(title: title, content: content, date: date)
            await onPublished(sha)
            isPublishing = false
            dismiss()
        } catch {
            isPublishing = false
            self.error = error.localizedDescription
        }
    }
}
