import Foundation

enum PhotoSelection: Identifiable {
    case website(WebsitePhoto)
    case local(PhotoDraft)

    var id: String {
        switch self {
        case .website(let photo): return "website-" + photo.id
        case .local(let draft): return "local-" + draft.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .website(let photo): return photo.title
        case .local(let draft): return draft.title
        }
    }
}
