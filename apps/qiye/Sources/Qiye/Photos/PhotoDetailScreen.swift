import SwiftUI

@MainActor
struct PhotoDetailScreen: View {
    let selection: PhotoSelection
    let store: PhotoLibraryStore
    let repository: GitHubRepository
    let canPublish: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false
    @State private var confirmsPublish = false
    @State private var isPublishing = false
    @State private var message: String?
    @State private var showsMessage = false
    @State private var publishedCommit: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geometry in
                    Group {
                        switch selection {
                        case .website(let photo):
                            RemotePhotoImage(url: photo.src, contentMode: .fit, bundledPreviewID: photo.id)
                        case .local(let draft):
                            LocalPhotoImage(url: store.fileURL(for: draft), contentMode: .fit, maximumPixelSize: 2_560)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityLabel(selection.title)
                }
                if case .local = selection {
                    publishingControls
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .disabled(isPublishing)
                }
                if case .local = selection, publishedCommit == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("删除本机副本", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
                            .disabled(isPublishing)
                    }
                }
            }
            .confirmationDialog("删除这张待发布照片？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("删除本机副本", role: .destructive) {
                    if case .local(let draft) = selection {
                        Task {
                            if await store.removeDraft(id: draft.id) { dismiss() }
                            else { message = store.error; showsMessage = true }
                        }
                    }
                }
            } message: {
                Text("系统相册与网站照片不会受到影响。")
            }
            .confirmationDialog("发布这张照片到个人网站？", isPresented: $confirmsPublish, titleVisibility: .visible) {
                Button("提交到 GitHub") { Task { await publish() } }
            } message: {
                Text("照片和相册索引将写入网站公开仓库，随后触发网站部署。")
            }
            .alert(publishedCommit == nil ? "发布状态" : "已提交到 GitHub", isPresented: $showsMessage) {
                Button("好", role: .cancel) { }
            } message: { Text(message ?? "") }
            .interactiveDismissDisabled(isPublishing)
        }
        .tint(.appAccent)
    }

    private var publishingControls: some View {
        VStack(spacing: 12) {
            if let commit = publishedCommit {
                Label("已提交，等待网站部署", systemImage: "checkmark.circle")
                Link("查看这次提交", destination: URL(string: "https://github.com/skqfly/skqfly.github.io/commit/\(commit)")!)
            } else {
                if !canPublish {
                    Text("先在右上角个人中心登录 GitHub，即可发布。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    confirmsPublish = true
                } label: {
                    if isPublishing { ProgressView("正在提交…").frame(maxWidth: .infinity) }
                    else { Label("发布到网站", systemImage: "arrow.up.circle").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canPublish || isPublishing)
            }
        }
        .padding(.vertical)
    }

    private func publish() async {
        guard case .local(let draft) = selection, canPublish, !isPublishing else { return }
        isPublishing = true
        defer { isPublishing = false }
        do {
            let photo = try await PhotoUploadPreparation.prepare(url: store.fileURL(for: draft))
            let commit = try await repository.addPhoto(
                data: photo.data, filename: draft.id.uuidString.lowercased() + ".jpg",
                width: photo.width, height: photo.height, title: "照片"
            )
            publishedCommit = commit
            message = "照片已写入 GitHub。部署结束后会出现在网站上，可在首页查看工作流状态。"
            showsMessage = true
            await store.refresh()
            _ = await store.removeDraft(id: draft.id)
        } catch {
            message = error.localizedDescription
            showsMessage = true
        }
    }
}
