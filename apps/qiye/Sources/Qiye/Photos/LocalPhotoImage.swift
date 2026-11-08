import SwiftUI
import ImageIO

struct LocalPhotoImage: View {
    let url: URL
    var fallbackURL: URL? = nil
    var contentMode: ContentMode = .fill
    var maximumPixelSize = 600
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark").font(.title2)
                    Text("无法读取本地照片").font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            image = nil
            failed = false
            let sourceURL = url
            let fallback = fallbackURL
            let pixelSize = maximumPixelSize
            let decoded = await Task.detached(priority: .userInitiated) {
                LocalPhotoImage.decode(sourceURL, maximumPixelSize: pixelSize)
                    ?? fallback.flatMap { LocalPhotoImage.decode($0, maximumPixelSize: pixelSize) }
            }.value
            guard !Task.isCancelled else { return }
            image = decoded
            failed = decoded == nil
        }
    }

    /// Prefers a cached thumbnail, then falls back to the full-size image so a
    /// valid photo never shows an error just because thumbnail creation was skipped.
    nonisolated private static func decode(_ sourceURL: URL, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return thumbnail
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
