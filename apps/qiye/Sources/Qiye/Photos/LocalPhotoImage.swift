import SwiftUI
import ImageIO

final class ImageThumbnailCache: @unchecked Sendable {
    static let shared = ImageThumbnailCache()
    private let cache = NSCache<NSURL, CGImage>()

    private init() {
        cache.countLimit = 240
    }

    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)
    }

    func setImage(_ image: CGImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    func remove(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}

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
            // Check in-memory thumbnail cache first for instant 0ms render
            if let cached = ImageThumbnailCache.shared.image(for: url) {
                image = cached
                failed = false
                return
            }
            if let fallback = fallbackURL, let cached = ImageThumbnailCache.shared.image(for: fallback) {
                image = cached
                failed = false
                return
            }
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
            if let decoded {
                ImageThumbnailCache.shared.setImage(decoded, for: sourceURL)
                image = decoded
                failed = false
            } else {
                image = nil
                failed = true
            }
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
