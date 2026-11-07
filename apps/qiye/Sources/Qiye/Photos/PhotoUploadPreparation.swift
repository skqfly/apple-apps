import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PreparedPhotoUpload: Sendable {
    let data: Data
    let width: Int
    let height: Int
}

enum PhotoUploadPreparation {
    static func prepare(url: URL) async throws -> PreparedPhotoUpload {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw PhotoUploadError.unreadable
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_560,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw PhotoUploadError.unreadable
            }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw PhotoUploadError.unreadable
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
            guard CGImageDestinationFinalize(destination), data.length <= 10 * 1_024 * 1_024 else {
                throw PhotoUploadError.tooLarge
            }
            return PreparedPhotoUpload(data: data as Data, width: image.width, height: image.height)
        }.value
    }
}

enum PhotoUploadError: LocalizedError {
    case unreadable, tooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: "无法处理这张照片，原始照片仍然保留在本机。"
        case .tooLarge: "处理后的照片超过 10 MB，请换一张较小的照片。"
        }
    }
}
