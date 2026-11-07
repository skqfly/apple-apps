import Foundation

struct MarkdownBlock: Identifiable, Sendable {
    let id: Int
    let kind: Kind

    enum Kind: Sendable {
        case heading(Int, String)
        case paragraph(String)
        case code(language: String, source: String)
        case quote(String)
        case listItem(marker: String, text: String, depth: Int)
        case image(alt: String, source: String, link: String?)
        case rule
        case table(String)
    }

    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0
        func append(_ kind: Kind) { blocks.append(MarkdownBlock(id: blocks.count, kind: kind)) }
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(while: { $0 == trimmed.first }))
                let language = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                index += 1
                var code: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                    code.append(lines[index]); index += 1
                }
                if index < lines.count { index += 1 }
                append(.code(language: language, source: code.joined(separator: "\n")))
                continue
            }
            if trimmed.hasPrefix("$$") || trimmed.hasPrefix("\\[") {
                let delimiter = trimmed.hasPrefix("$$") ? "$$" : "\\]"
                var math = [line]
                let opensAndCloses = trimmed.hasPrefix("$$") && trimmed.count > 4 && trimmed.hasSuffix("$$")
                index += 1
                if !opensAndCloses {
                    while index < lines.count {
                        math.append(lines[index])
                        let closes = lines[index].trimmingCharacters(in: .whitespaces).hasSuffix(delimiter)
                        index += 1
                        if closes { break }
                    }
                }
                append(.code(language: "LaTeX", source: math.joined(separator: "\n")))
                continue
            }
            if let heading = heading(trimmed) {
                append(.heading(heading.0, heading.1)); index += 1; continue
            }
            if index + 1 < lines.count {
                let underline = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if underline.count >= 3, Set(underline).count == 1, underline.first == "=" || underline.first == "-" {
                    append(.heading(underline.first == "=" ? 1 : 2, trimmed)); index += 2; continue
                }
            }
            if isRule(trimmed) { append(.rule); index += 1; continue }
            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                append(.quote(quote.joined(separator: "\n"))); continue
            }
            if let item = listItem(line) {
                var text = item.text
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                      lines[index].first?.isWhitespace == true, listItem(lines[index]) == nil {
                    text += "\n" + lines[index].trimmingCharacters(in: .whitespaces)
                    index += 1
                }
                append(.listItem(marker: item.marker, text: text, depth: item.depth)); continue
            }
            if trimmed.hasPrefix("|"), index + 1 < lines.count, lines[index + 1].contains("---") {
                var table: [String] = []
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    table.append(lines[index]); index += 1
                }
                append(.table(table.joined(separator: "\n"))); continue
            }
            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                var code: [String] = []
                while index < lines.count && (lines[index].hasPrefix("    ") || lines[index].hasPrefix("\t")) {
                    code.append(String(lines[index].dropFirst(lines[index].hasPrefix("\t") ? 1 : 4)))
                    index += 1
                }
                append(.code(language: "", source: code.joined(separator: "\n"))); continue
            }
            var paragraph = [line]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || heading(next) != nil || next.hasPrefix("```") || next.hasPrefix("~~~") ||
                    next.hasPrefix(">") || next.hasPrefix("$$") || next.hasPrefix("\\[") ||
                    listItem(lines[index]) != nil || isRule(next) { break }
                paragraph.append(lines[index]); index += 1
            }
            for kind in splitImages(paragraph.joined(separator: "\n")) { append(kind) }
        }
        return blocks
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return (level, text.replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression))
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        return compact.count >= 3 && Set(compact).count == 1 && ["-", "*", "_"].contains(String(compact.prefix(1)))
    }

    private static func listItem(_ line: String) -> (marker: String, text: String, depth: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let depth = min((line.count - trimmed.count) / 2, 4)
        for prefix in ["- ", "* ", "+ "] where trimmed.hasPrefix(prefix) {
            var text = String(trimmed.dropFirst(2))
            var marker = "•"
            if text.hasPrefix("[ ] ") { marker = "☐"; text = String(text.dropFirst(4)) }
            if text.lowercased().hasPrefix("[x] ") { marker = "☑"; text = String(text.dropFirst(4)) }
            return (marker, text, depth)
        }
        let digits = trimmed.prefix(while: { $0.isNumber })
        let rest = trimmed.dropFirst(digits.count)
        guard !digits.isEmpty, rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return ("\(digits).", String(rest.dropFirst(2)), depth)
    }

    private static func splitImages(_ text: String) -> [Kind] {
        // Standalone and linked Markdown images. Text around an image becomes paragraphs.
        let pattern = #"(?:\[)?!\[([^\]]*)\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)(?:\]\(([^)]+)\))?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [.paragraph(text)] }
        let ns = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [.paragraph(text)] }
        var result: [Kind] = []
        var cursor = 0
        for match in matches {
            let before = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty { result.append(.paragraph(before)) }
            let link = match.range(at: 3).location == NSNotFound ? nil : ns.substring(with: match.range(at: 3))
            result.append(.image(alt: ns.substring(with: match.range(at: 1)), source: ns.substring(with: match.range(at: 2)), link: link))
            cursor = NSMaxRange(match.range)
        }
        let remainder = ns.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty { result.append(.paragraph(remainder)) }
        return result
    }
}
