import SwiftUI

struct MarkdownBlocks: View {
    private let blocks: [MarkdownBlock]
    private let baseURL: URL

    init(_ markdown: String, baseURL: URL = GitHubRepository.websiteURL) {
        blocks = MarkdownBlock.parse(markdown)
        self.baseURL = baseURL
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(blocks) { block in
                blockView(block.kind)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
        .tint(.appAccent)
    }

    @ViewBuilder
    private func blockView(_ kind: MarkdownBlock.Kind) -> some View {
        switch kind {
        case let .heading(level, text):
            Text(inline(text))
                .font(headingFont(level)).fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, level < 3 ? 12 : 6)
        case let .paragraph(text):
            Text(inline(text)).font(.body).lineSpacing(5)
        case let .code(language, source):
            VStack(alignment: .leading, spacing: 10) {
                if !language.isEmpty { Text(language).font(.caption).foregroundStyle(.secondary) }
                ScrollView(.horizontal) {
                    Text(verbatim: source)
                        .font(.system(.callout, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.bottom, 2)
                }
                .accessibilityLabel(language.isEmpty ? "代码" : "\(language) 代码")
            }
            .padding(16)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        case let .quote(text):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Color.appAccent).frame(width: 3)
                Text(inline(text)).foregroundStyle(.secondary).lineSpacing(4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
        case let .listItem(marker, text, depth):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: marker).foregroundStyle(.secondary)
                Text(inline(text)).lineSpacing(4)
            }
            .padding(.leading, Double(depth) * 16)
        case let .image(alt, source, link):
            if let url = imageURL(source) {
                if let link, let destination = imageURL(link) {
                    Link(destination: destination) { markdownImage(url: url, alt: alt) }
                } else {
                    Link(destination: url) { markdownImage(url: url, alt: alt) }
                }
            } else {
                Label(alt.isEmpty ? "图片地址不可用" : alt, systemImage: "photo")
                    .foregroundStyle(.secondary)
            }
        case .rule:
            Divider().padding(.vertical, 8)
        case let .table(source):
            MarkdownTable(source: source, baseURL: baseURL)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        func markdown(_ value: String) -> AttributedString {
            (try? AttributedString(markdown: value,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace), baseURL: baseURL)) ?? AttributedString(value)
        }
        // Keep LaTeX commands intact rather than allowing Markdown escapes to alter them.
        let pattern = #"(?<!\\)\$[^$\n]+\$|\\\([^\n]*?\\\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return markdown(text) }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return markdown(text) }
        var result = AttributedString()
        var cursor = 0
        for match in matches {
            result.append(markdown(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            var formula = AttributedString(ns.substring(with: match.range))
            formula.font = .system(.body, design: .monospaced)
            result.append(formula)
            cursor = NSMaxRange(match.range)
        }
        result.append(markdown(ns.substring(from: cursor)))
        return result
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    private func imageURL(_ path: String) -> URL? {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              ["https", "http"].contains(url.scheme ?? "") else { return nil }
        return url
    }

    private func markdownImage(url: URL, alt: String) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFit()
            case .failure:
                Label("图片暂时无法加载，轻点在浏览器打开", systemImage: "photo")
                    .font(.callout).foregroundStyle(.secondary).padding(24)
            default:
                ProgressView().frame(maxWidth: .infinity).frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 600)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(alt.isEmpty ? "文章图片" : alt)
        .accessibilityHint("轻点查看原图")
    }
}

private struct MarkdownTable: View {
    let source: String
    let baseURL: URL

    private var rows: [[String]] {
        source.components(separatedBy: "\n").enumerated().compactMap { index, line in
            guard index != 1 else { return nil }
            var cells = line.components(separatedBy: "|")
            if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
            if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
            return cells.map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { row in
                    GridRow {
                        ForEach(Array(row.element.enumerated()), id: \.offset) { cell in
                            Text((try? AttributedString(markdown: cell.element, baseURL: baseURL)) ?? AttributedString(cell.element))
                                .font(row.offset == 0 ? .headline : .body)
                                .frame(minWidth: 100, maxWidth: 300, alignment: .leading)
                        }
                    }
                    if row.offset == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                }
            }
            .padding(14)
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
