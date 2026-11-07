import SwiftUI

struct RemotePhotoImage: View {
    let url: URL
    var contentMode: ContentMode = .fill
    var allowsRetry = true
    var bundledPreviewID: String?
    var prefersBundledPreview = false
    @State private var attempt = 0

    private var bundledURL: URL? {
        guard let bundledPreviewID else { return nil }
        return Bundle.main.url(forResource: bundledPreviewID, withExtension: "jpg", subdirectory: "PhotoPreviews")
            ?? Bundle.main.url(forResource: bundledPreviewID, withExtension: "jpg")
    }

    var body: some View {
        if prefersBundledPreview, let bundledURL {
            LocalPhotoImage(url: bundledURL, contentMode: contentMode)
        } else {
            remoteImage
        }
    }

    private var remoteImage: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                if let bundledURL {
                    LocalPhotoImage(url: bundledURL, contentMode: contentMode, maximumPixelSize: 1_600)
                        .overlay(alignment: .bottomTrailing) {
                            ProgressView().padding()
                        }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                if let bundledURL {
                    LocalPhotoImage(url: bundledURL, contentMode: contentMode, maximumPixelSize: 1_600)
                        .overlay(alignment: .bottom) {
                            if allowsRetry {
                                Button("正在显示预览，重试原图", systemImage: "arrow.clockwise") { attempt += 1 }
                                    .font(.caption)
                                    .buttonStyle(.borderedProminent)
                                    .padding()
                            }
                        }
                } else {
                    failurePlaceholder
                }
            @unknown default:
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .id(attempt)
    }

    private var failurePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark").font(.title2)
            Text("图像加载失败").font(.caption)
            if allowsRetry {
                Button("重新加载") { attempt += 1 }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
