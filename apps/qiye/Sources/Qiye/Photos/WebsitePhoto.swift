import Foundation

struct WebsitePhoto: Identifiable, Equatable, Sendable {
    let id: String
    let src: URL
    let width: Int
    let height: Int
    let alt: String
    let preview: URL
    let previewLarge: URL

    var title: String { alt.isEmpty ? "网站照片" : alt }

    static func decode(_ data: Data, relativeTo baseURL: URL) throws -> [WebsitePhoto] {
        struct Entry: Decodable {
            let src: String
            let width: Int
            let height: Int
            let alt: String
            let preview: String?
            let previewLarge: String?
        }
        let entries = try JSONDecoder().decode([String: Entry].self, from: data)
        func resolve(_ path: String) throws -> URL {
            guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
                  url.scheme == "https", url.host != nil else {
                throw URLError(.badURL)
            }
            return url
        }
        return try entries.keys.sorted().map { id in
            guard let entry = entries[id], entry.width > 0, entry.height > 0 else {
                throw CocoaError(.coderReadCorrupt)
            }
            return try WebsitePhoto(
                id: id, sourcePath: entry.src, src: resolve(entry.src), width: entry.width, height: entry.height,
                alt: entry.alt, preview: resolve(entry.preview ?? entry.src),
                previewLarge: resolve(entry.previewLarge ?? entry.src)
            )
        }
    }
}
