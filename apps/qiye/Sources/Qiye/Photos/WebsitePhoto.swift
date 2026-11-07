import Foundation

struct WebsitePhoto: Identifiable, Equatable, Sendable {
    let id: String
    let src: URL
    let width: Int
    let height: Int
    let alt: String
    let preview: URL
    let previewLarge: URL
    let publishedAt: Date?

    var title: String { alt.isEmpty ? "网站照片" : alt }

    static func decode(_ data: Data, relativeTo baseURL: URL) throws -> [WebsitePhoto] {
        struct Entry: Decodable {
            let src: String
            let width: Int
            let height: Int
            let alt: String
            let preview: String?
            let previewLarge: String?
            let publishedAt: String?
        }
        let entries = try JSONDecoder().decode([String: Entry].self, from: data)
        func resolve(_ path: String) throws -> URL {
            guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
                  url.scheme == "https", url.host != nil else {
                throw URLError(.badURL)
            }
            return url
        }
        // JSONDecoder does not preserve object order, and older publishes sorted keys.
        // Timestamped uploads come first; older photos keep the saved wall order.
        let savedOrder = try objectKeyOrder(in: data)
        let ranked = try savedOrder.map { id in
            guard let entry = entries[id], entry.width > 0, entry.height > 0 else {
                throw CocoaError(.coderReadCorrupt)
            }
            return try WebsitePhoto(
                id: id, src: resolve(entry.src), width: entry.width, height: entry.height,
                alt: entry.alt, preview: resolve(entry.preview ?? entry.src),
                previewLarge: resolve(entry.previewLarge ?? entry.src),
                publishedAt: entry.publishedAt.flatMap(Self.parseTimestamp)
            )
        }
        return ranked.enumerated().sorted { lhs, rhs in
            switch (lhs.element.publishedAt, rhs.element.publishedAt) {
            case let (left?, right?):
                return left == right ? lhs.offset < rhs.offset : left > right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static func objectKeyOrder(in data: Data) throws -> [String] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return Array(object.keys)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
