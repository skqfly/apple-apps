import Foundation

struct WebsitePhoto: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let sourcePath: String
    let src: URL
    let width: Int
    let height: Int
    let alt: String
    let preview: URL
    let previewLarge: URL

    var title: String { alt.isEmpty ? "网站照片" : alt }

    init(id: String, src: URL, width: Int, height: Int, alt: String, preview: URL, previewLarge: URL) {
        self.init(id: id, sourcePath: src.path, src: src, width: width, height: height, alt: alt, preview: preview, previewLarge: previewLarge)
    }

    init(id: String, sourcePath: String, src: URL, width: Int, height: Int, alt: String, preview: URL, previewLarge: URL) {
        self.id = id
        self.sourcePath = sourcePath
        self.src = src
        self.width = width
        self.height = height
        self.alt = alt
        self.preview = preview
        self.previewLarge = previewLarge
    }

    static func decode(_ data: Data, relativeTo baseURL: URL) throws -> [WebsitePhoto] {
        struct Entry: Decodable {
            let src: String
            let width: Int
            let height: Int
            let alt: String
            let preview: String?
            let previewLarge: String?
        }
        // The top-level key order is the website photo order (`Object.values` in
        // Astro). A plain JSONDecoder/Dictionary sorts keys, so parse keys in source
        // order and decode each value separately.
        let ordered = try orderedEntries(data)
        func resolve(_ path: String) throws -> URL {
            guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
                  url.scheme == "https", url.host != nil else {
                throw URLError(.badURL)
            }
            return url
        }
        return try ordered.map { id, valueData in
            let entry = try JSONDecoder().decode(Entry.self, from: valueData)
            guard entry.width > 0, entry.height > 0 else {
                throw CocoaError(.coderReadCorrupt)
            }
            return try WebsitePhoto(
                id: id, sourcePath: entry.src, src: resolve(entry.src), width: entry.width, height: entry.height,
                alt: entry.alt, preview: resolve(entry.preview ?? entry.src),
                previewLarge: resolve(entry.previewLarge ?? entry.src)
            )
        }
    }

    /// Returns top-level object entries in source order. Each value is returned as
    /// raw JSON bytes so it can be decoded independently.
    private static func orderedEntries(_ data: Data) throws -> [(String, Data)] {
        let bytes = [UInt8](data)
        var i = 0
        func skipWhitespace() {
            while i < bytes.count {
                switch bytes[i] {
                case 0x20, 0x09, 0x0A, 0x0D: i += 1
                default: return
                }
            }
        }
        skipWhitespace()
        guard i < bytes.count, bytes[i] == 0x7B else { throw CocoaError(.coderReadCorrupt) }
        i += 1
        var result: [(String, Data)] = []
        while true {
            skipWhitespace()
            guard i < bytes.count else { throw CocoaError(.coderReadCorrupt) }
            if bytes[i] == 0x7D { i += 1; break }
            let key = try parseString(&i, bytes)
            skipWhitespace()
            guard i < bytes.count, bytes[i] == 0x3A else { throw CocoaError(.coderReadCorrupt) }
            i += 1
            skipWhitespace()
            let valueStart = i
            try skipValue(&i, bytes)
            result.append((key, Data(bytes[valueStart..<i])))
            skipWhitespace()
            if i < bytes.count, bytes[i] == 0x2C { i += 1; continue }
            if i < bytes.count, bytes[i] == 0x7D { i += 1; break }
            throw CocoaError(.coderReadCorrupt)
        }
        return result
    }

    private static func parseString(_ i: inout Int, _ bytes: [UInt8]) throws -> String {
        guard i < bytes.count, bytes[i] == 0x22 else { throw CocoaError(.coderReadCorrupt) }
        i += 1
        var out: [UInt8] = []
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x22 { i += 1; break }
            if b == 0x5C {
                i += 1
                guard i < bytes.count else { throw CocoaError(.coderReadCorrupt) }
                let escaped = bytes[i]
                switch escaped {
                case 0x22, 0x5C, 0x2F: out.append(escaped)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x75:
                    guard i + 4 < bytes.count else { throw CocoaError(.coderReadCorrupt) }
                    let hex = String(decoding: bytes[(i + 1)..<(i + 5)], as: UTF8.self)
                    guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else {
                        throw CocoaError(.coderReadCorrupt)
                    }
                    out.append(contentsOf: String(scalar).utf8)
                    i += 4
                default: throw CocoaError(.coderReadCorrupt)
                }
                i += 1
            } else {
                out.append(b)
                i += 1
            }
        }
        return String(bytes: out, encoding: .utf8) ?? ""
    }

    private static func skipValue(_ i: inout Int, _ bytes: [UInt8]) throws {
        guard i < bytes.count else { throw CocoaError(.coderReadCorrupt) }
        switch bytes[i] {
        case 0x7B, 0x5B:
            let open = bytes[i]
            let close: UInt8 = open == 0x7B ? 0x7D : 0x5D
            i += 1
            var depth = 1
            var inString = false
            var escaped = false
            while i < bytes.count && depth > 0 {
                let b = bytes[i]
                if inString {
                    if escaped { escaped = false }
                    else if b == 0x5C { escaped = true }
                    else if b == 0x22 { inString = false }
                } else {
                    if b == 0x22 { inString = true }
                    else if b == open { depth += 1 }
                    else if b == close { depth -= 1 }
                }
                i += 1
            }
            guard depth == 0 else { throw CocoaError(.coderReadCorrupt) }
        case 0x22:
            i += 1
            var escaped = false
            while i < bytes.count {
                let b = bytes[i]
                if escaped { escaped = false }
                else if b == 0x5C { escaped = true }
                else if b == 0x22 { i += 1; break }
                i += 1
            }
        default:
            while i < bytes.count {
                let b = bytes[i]
                if b == 0x2C || b == 0x7D || b == 0x5D { break }
                i += 1
            }
        }
    }
}
