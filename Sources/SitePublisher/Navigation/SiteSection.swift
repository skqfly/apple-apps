import SwiftUI

enum SiteSection: String, CaseIterable, Identifiable {
    case blog
    case projects
    case talks
    case friends

    var id: Self { self }

    var title: String {
        switch self {
        case .blog: "Blog"
        case .projects: "Projects"
        case .talks: "Talks"
        case .friends: "Friends"
        }
    }

    var symbolName: String {
        switch self {
        case .blog: "text.alignleft"
        case .projects: "square.stack.3d.up"
        case .talks: "person.wave.2"
        case .friends: "person.2"
        }
    }

    var summary: String {
        switch self {
        case .blog:
            "文章草稿、发布状态与分类。"
        case .projects:
            "公开项目的说明、标签与链接。"
        case .talks:
            "分享记录、日期与配图。"
        case .friends:
            "友情链接与推荐站点。"
        }
    }
}
