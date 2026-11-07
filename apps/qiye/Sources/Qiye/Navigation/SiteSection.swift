import SwiftUI

enum SiteSection: String, CaseIterable, Identifiable {
    case home, blog, talks, photos
    var id: Self { self }

    var title: String {
        switch self {
        case .home: "首页"
        case .blog: "博客"
        case .talks: "说说"
        case .photos: "照片"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house"
        case .blog: "doc.text"
        case .talks: "text.bubble"
        case .photos: "photo.on.rectangle.angled"
        }
    }
}
