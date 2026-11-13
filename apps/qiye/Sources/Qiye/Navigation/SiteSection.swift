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

    var selectedSymbol: String {
        switch self {
        case .home: "square.stack.fill"
        case .blog: "doc.text.fill"
        case .talks: "text.bubble.fill"
        case .photos: "photo.on.rectangle.angled"
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
