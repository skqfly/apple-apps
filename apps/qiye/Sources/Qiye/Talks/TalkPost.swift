import Foundation

struct TalkPost: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let title: String
    let date: Date
    let description: String
    let images: [TalkImage]

    var content: String { description }

    private enum CodingKeys: String, CodingKey { case id, title, date, description, images }

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

struct TalkImage: Decodable, Hashable, Sendable, Identifiable {
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
              ["https", "http"].contains(url.scheme ?? "") else { return nil }
        return url
    }
}
