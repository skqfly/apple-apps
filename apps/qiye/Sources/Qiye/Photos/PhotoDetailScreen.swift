import SwiftUI

@MainActor
struct PhotoDetailScreen: View {
    let selection: PhotoSelection
    let store: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false
    @State private var deleteFailed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    Group {
                        switch selection {
                        case .website(let photo):
                            RemotePhotoImage(url: photo.src, contentMode: .fit, bundledPreviewID: photo.id)
                        case .local(let draft):
                            LocalPhotoImage(url: store.fileURL(for: draft), contentMode: .fit, maximumPixelSize: 2_400)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
                .accessibilityLabel(selection.title)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text(selection.title).font(.headline).textSelection(.enabled)
                    switch selection {
                    case .website(let photo):
                        Label("网站照片 · \(photo.width) × \(photo.height)", systemImage: "globe")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .local(let draft):
                        Label("仅保存在本机", systemImage: "iphone")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(draft.importedAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(.background)
            .navigationTitle("照片详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
                if case .local = selection {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("删除本地照片", systemImage: "trash", role: .destructive) {
                            confirmsDeletion = true
                        }
                        .disabled(store.isImporting || store.isDeleting)
                    }
                }
            }
            .confirmationDialog("删除这张本地照片？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("删除本地照片", role: .destructive) {
                    if case .local(let draft) = selection {
                        Task {
                            if await store.removeDraft(id: draft.id) { dismiss() }
                            else { deleteFailed = true }
                        }
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将删除本应用保存的副本，系统相册与网站中的照片不受影响。")
            }
            .alert("未能删除照片", isPresented: $deleteFailed) {
                Button("好", role: .cancel) { }
            } message: {
                Text(store.error ?? "本地照片正在处理中，请稍后重试。")
            }
        }
    }
}
