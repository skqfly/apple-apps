import Foundation

struct TalkPost: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let date: Date
    let description: String
    let images: [TalkImage]

    var content: String { description }

    private enum CodingKeys: String, CodingKey { case id, title, date, description, images }

    init(id: String, title: String = "", date: Date, description: String, images: [TalkImage]) {
        self.id = id
        self.title = title
        self.date = date
        self.description = description
        self.images = images
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(ContentDate.string(date), forKey: .date)
        try container.encode(description, forKey: .description)
        try container.encode(images, forKey: .images)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        let dateString = try container.decode(String.self, forKey: .date)
        guard let parsed = ContentDate.parse(dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Invalid content date")
        }
        date = parsed
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        images = try container.decodeIfPresent([TalkImage].self, forKey: .images) ?? []
    }
}

struct TalkImage: Codable, Hashable, Sendable, Identifiable {
    var id: String { src }
    let src: String
    let width: Int?
    let height: Int?
    let alt: String?
    let preview: String?
    let previewLarge: String?

    init(src: String, width: Int?, height: Int?, alt: String?, preview: String?, previewLarge: String?) {
        self.src = src
        self.width = width
        self.height = height
        self.alt = alt
        self.preview = preview
        self.previewLarge = previewLarge
    }

    var url: URL? { resolve(previewLarge ?? preview ?? src) }
    var originalURL: URL? { resolve(src) }
    var aspectRatio: Double {
        guard let width, let height, width > 0, height > 0 else { return 4.0 / 3.0 }
        return Double(width) / Double(height)
    }

    private func resolve(_ path: String) -> URL? {
        guard let url = URL(string: path, relativeTo: GitHubRepository.websiteURL)?.absoluteURL,
              ["https", "http", "file"].contains(url.scheme ?? "") else { return nil }
        return url
    }
}
