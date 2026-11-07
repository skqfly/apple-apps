import Foundation

struct BlogPost: Identifiable, Hashable, Sendable {
    var id: String { path }
    let title: String
    let date: Date
    let description: String
    let path: String
    let body: String
    let metadata: [String: String]

    var category: String? { metadata["category"] }
    var imageURL: URL? {
        guard let value = metadata["image.url"] ?? metadata["image"],
              !value.hasPrefix("{"), !value.isEmpty else { return nil }
        return URL(string: value, relativeTo: GitHubRepository.websiteURL)?.absoluteURL
    }
    var websiteURL: URL {
        let slug = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return GitHubRepository.websiteURL.appending(path: "blog/\(slug)")
    }

    static func parse(_ markdown: String, path: String) -> BlogPost {
        let parsed = Frontmatter.parse(markdown)
        let fallbackTitle = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return BlogPost(
            title: parsed.metadata["title"].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
            date: ContentDate.parse(parsed.metadata["pubDate"] ?? parsed.metadata["date"] ?? "") ?? .distantPast,
            description: parsed.metadata["description"] ?? "",
            path: path, body: parsed.body, metadata: parsed.metadata
        )
    }
}

enum Frontmatter {
    struct Parsed: Sendable { let metadata: [String: String]; let body: String }

    /// Supports scalar fields, quoted values, YAML literal/folded multiline fields,
    /// and the website's JSON/nested `image: {url, alt}` convention.
    static func parse(_ markdown: String) -> Parsed {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" || $0 == "..." }) else {
            return Parsed(metadata: [:], body: normalized)
        }
        var fields: [String: String] = [:]
        var index = 1
        var parentKey: String?
        while index < end {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else {
                index += 1; continue
            }
            let key = String(trimmed[..<colon])
            let rawValue = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let isIndented = line.first?.isWhitespace == true
            let field = isIndented ? parentKey.map { "\($0).\(key)" } ?? key : key
            if !isIndented { parentKey = rawValue.isEmpty ? key : nil }
            if ["|", "|-", "|+", ">", ">-", ">+"].contains(rawValue) {
                var values: [String] = []
                index += 1
                while index < end {
                    let next = lines[index]
                    if !next.isEmpty && next.first?.isWhitespace != true { break }
                    values.append(next.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                fields[field] = values.joined(separator: rawValue.hasPrefix(">") ? " " : "\n").trimmingCharacters(in: .newlines)
                continue
            }
            fields[field] = scalar(rawValue)
            if key == "image", let data = rawValue.data(using: .utf8),
               let image = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                fields["image.url"] = image["url"]
                fields["image.alt"] = image["alt"]
            }
            index += 1
        }
        return Parsed(metadata: fields, body: lines.dropFirst(end + 1).joined(separator: "\n").trimmingCharacters(in: .newlines))
    }

    private static func scalar(_ raw: String) -> String {
        guard raw.count >= 2 else { return raw }
        if raw.hasPrefix("\""), raw.hasSuffix("\"") {
            if let data = raw.data(using: .utf8), let value = try? JSONDecoder().decode(String.self, from: data) { return value }
            return String(raw.dropFirst().dropLast())
        }
        if raw.hasPrefix("'"), raw.hasSuffix("'") {
            return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return raw.components(separatedBy: " #").first ?? raw
    }
}
