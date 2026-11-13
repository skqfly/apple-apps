import SwiftUI

enum SiteSection: String, CaseIterable, Identifiable {
    case home, blog, talks, photos
    var id: Self { self }

    var title: String {
        switch self {
        case .home: "收藏"
        case .blog: "文章"
        case .talks: "说说"
        case .photos: "图片"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "square.stack"
        case .blog: "doc.text"
        case .talks: "text.bubble"
        case .photos: "photo.on.rectangle.angled"
        }
    }
}
