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
    @State private var publicationUncertain: Bool

    init(selection: PhotoSelection, store: PhotoLibraryStore, repository: GitHubRepository, canPublish: Bool) {
        self.selection = selection
        self.store = store
        self.repository = repository
        self.canPublish = canPublish
        if case .local(let draft) = selection {
            _publishedCommit = State(initialValue: draft.publishedCommit)
            _publicationUncertain = State(initialValue: draft.publicationUncertain ?? false)
        } else {
            _publishedCommit = State(initialValue: nil)
            _publicationUncertain = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geometry in
                    Group {
                        switch selection {
                        case .website(let photo):
                            RemotePhotoImage(url: photo.src, contentMode: .fit, bundledPreviewID: store.bundledPreviewID(for: photo))
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
            .accessibilityIdentifier("photo-detail-screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .disabled(isPublishing)
                }
                if case .local = selection {
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
            .confirmationDialog(publicationUncertain ? "已核实 GitHub 中没有这次提交？" : "发布这张照片到个人网站？", isPresented: $confirmsPublish, titleVisibility: .visible) {
                Button(publicationUncertain ? "已核实未提交，重新发布" : "提交到 GitHub") {
                    publicationUncertain = false
                    Task { await publish() }
                }
            } message: {
                Text(publicationUncertain ? "上次连接中断，提交可能已经成功。请先查看 GitHub 提交记录；重复发布会生成另一张照片。" : "照片和相册索引将写入网站公开仓库，随后触发网站部署。")
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
                if publicationUncertain {
                    Text("上次提交结果待核实，请先检查 GitHub 记录，避免重复发布。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("查看 GitHub 提交记录", destination: URL(string: "https://github.com/\(GitHubRepository.owner)/\(GitHubRepository.name)/commits/\(GitHubRepository.branch)")!)
                }
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
                .disabled(!canPublish || isPublishing || store.isImporting || store.isDeleting)
            }
        }
        .padding(.vertical)
    }

    private func publish() async {
        guard case .local(let draft) = selection, canPublish, !isPublishing,
              publishedCommit == nil, !store.isImporting, !store.isDeleting else { return }
        isPublishing = true
        defer { isPublishing = false }
        do {
            let photo = try await PhotoUploadPreparation.prepare(url: store.fileURL(for: draft))
            let commit = try await repository.addPhoto(
                data: photo.data, filename: draft.id.uuidString.lowercased() + ".jpg",
                width: photo.width, height: photo.height, title: "照片"
            )
            publishedCommit = commit
            let recorded = await store.recordPublication(id: draft.id, commit: commit)
            let removed = await store.removeDraft(id: draft.id)
            message = "照片已写入 GitHub。部署结束后会出现在网站上，可在首页查看工作流状态。"
            if !removed {
                message! += recorded
                    ? " 本机副本未能移除，已标记为已提交，不会再次发布。"
                    : " 本机提交状态保存失败，请先检查 GitHub 记录，避免重复发布。"
            }
            showsMessage = true
            await store.refresh()
        } catch GitHubError.publishUncertain {
            publicationUncertain = true
            let recorded = await store.recordPublication(id: draft.id, commit: nil, uncertain: true)
            message = GitHubError.publishUncertain.localizedDescription
            if !recorded { message! += " 本机提交状态未能保存。" }
            showsMessage = true
        } catch {
            message = error.localizedDescription
            showsMessage = true
        }
    }
}
