import SwiftUI

@MainActor
struct PhotoDetailScreen: View {
    let selection: PhotoSelection
    let store: PhotoLibraryStore
    let repository: GitHubRepository
    let pending: PendingChangesStore
    let canPublish: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsLocalDelete = false
    @State private var confirmsUnpublish = false
    @State private var confirmsDelete = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var showsMessage = false

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
                managementControls
            }
            .padding(.horizontal)
            .padding(.bottom)
            .background(Color.appBackground)
            .accessibilityIdentifier("photo-detail-screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .disabled(isWorking)
                }
                if case .local = selection {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("删除本机副本", systemImage: "trash", role: .destructive) { confirmsLocalDelete = true }
                            .disabled(isWorking)
                    }
                }
            }
            .confirmationDialog("删除这张待发布照片？", isPresented: $confirmsLocalDelete, titleVisibility: .visible) {
                Button("删除本机副本", role: .destructive) {
                    if case .local(let draft) = selection {
                        Task {
                            if await store.removeDraft(id: draft.id) { dismiss() }
                            else { message = store.error; showsMessage = true }
                        }
                    }
                }
            } message: { Text("系统相册与网站照片不会受到影响。") }
            .confirmationDialog("下架这张照片？", isPresented: $confirmsUnpublish, titleVisibility: .visible) {
                Button("下架", role: .destructive) {
                    if case .website(let photo) = selection {
                        pending.stageUnpublishPhoto(photoID: photo.id, source: photo.src.path)
                        message = "已暂存下架，去首页一键推送后生效。"
                        showsMessage = true
                    }
                }
            } message: { Text("照片会从网站消失，但图片文件仍保留在仓库里。") }
            .confirmationDialog("删除这张照片？", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if case .website(let photo) = selection {
                        pending.stageDeletePhoto(photoID: photo.id, source: photo.src.path)
                        message = "已暂存删除，去首页一键推送后生效。"
                        showsMessage = true
                    }
                }
            } message: { Text("照片会从网站和仓库中一并删除。") }
            .alert("操作状态", isPresented: $showsMessage) {
                Button("好", role: .cancel) { }
            } message: { Text(message ?? "") }
            .interactiveDismissDisabled(isWorking)
        }
        .tint(.appAccent)
    }

    @ViewBuilder
    private var managementControls: some View {
        switch selection {
        case .local:
            VStack(spacing: 12) {
                if !canPublish {
                    Text("先在左上角个人中心登录 GitHub，即可发布。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    Task { await stageLocal() }
                } label: {
                    if isWorking { ProgressView("正在暂存…").frame(maxWidth: .infinity) }
                    else { Label("暂存并稍后推送", systemImage: "tray.and.arrow.up").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canPublish || isWorking || store.isImporting || store.isDeleting)
                Text("暂存后可在首页一次性推送，避免每个动作都提交。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical)
        case .website:
            VStack(spacing: 12) {
                if !canPublish {
                    Text("登录 GitHub 后可管理网站照片。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            confirmsUnpublish = true
                        } label: {
                            Label("下架", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            confirmsDelete = true
                        } label: {
                            Label("删除", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .disabled(isWorking)
                    Text("下架仅从网站移除，删除会连同图片文件一起移除。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical)
        }
    }

    private func stageLocal() async {
        guard case .local(let draft) = selection, canPublish, !isWorking,
              !store.isImporting, !store.isDeleting else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let photo = try await PhotoUploadPreparation.prepare(url: store.fileURL(for: draft))
            try pending.stagePhoto(draftID: draft.id, jpeg: photo.data, width: photo.width, height: photo.height)
            _ = await store.removeDraft(id: draft.id)
            message = "已暂存到首页，稍后一键推送。"
            showsMessage = true
            await store.refresh()
            dismiss()
        } catch {
            message = error.localizedDescription
            showsMessage = true
        }
    }
}
