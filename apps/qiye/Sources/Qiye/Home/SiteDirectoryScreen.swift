import SwiftUI
import WebKit

@Observable @MainActor
final class SiteDirectoryStore {
    private(set) var projects: [SiteDirectoryEntry] = []
    private(set) var friends: [SiteDirectoryEntry] = []
    private(set) var error: String?
    private(set) var isLoading = false
    private var revision = 0
    private let repository: GitHubRepository

    init(repository: GitHubRepository) {
        self.repository = repository
        if let url = Bundle.main.url(forResource: "site", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let site = try? JSONDecoder().decode(SiteDirectoryDocument.self, from: data) {
            projects = site.projectsPageContent.projects
            friends = site.friendsPageContent.friends
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let capturedRevision = revision
        defer { isLoading = false }
        do {
            let data = try await repository.getRepositoryFile(path: SiteDirectoryDocument.path)
            let site = try JSONDecoder().decode(SiteDirectoryDocument.self, from: data)
            guard revision == capturedRevision else { return }
            projects = site.projectsPageContent.projects
            friends = site.friendsPageContent.friends
            error = nil
        } catch is CancellationError { }
        catch {
            guard revision == capturedRevision else { return }
            self.error = "暂时无法更新，正在显示已保存的内容。"
        }
    }

    func save(_ draft: SiteDirectoryEntry, kind: DirectoryKind,
              replacing original: SiteDirectoryEntry?) async throws -> SiteDirectoryEntry {
        let entry = try await repository.saveDirectoryEntry(draft, kind: kind, replacing: original)
        revision += 1
        if kind == .projects { Self.update(&projects, entry: entry, replacing: original) }
        else { Self.update(&friends, entry: entry, replacing: original) }
        return entry
    }

    private static func update(_ entries: inout [SiteDirectoryEntry], entry: SiteDirectoryEntry,
                               replacing original: SiteDirectoryEntry?) {
        if let index = entries.firstIndex(where: { $0.url == (original?.url ?? entry.url) }) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
        }
    }
}

@MainActor
struct SiteDirectoryScreen: View {
    let store: SiteDirectoryStore
    let kind: DirectoryKind
    let canEdit: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: SiteDirectoryEntry?
    @State private var isAdding = false

    private var entries: [SiteDirectoryEntry] {
        kind == .projects ? store.projects : store.friends
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = store.error {
                    ContentStatus(message: error) { await store.refresh() }
                }
                if entries.isEmpty {
                    ContentUnavailableView("暂无\(kind.title)", systemImage: kind.symbol)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                        count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(entries) { entry in
                        Button {
                            selected = entry
                            Haptics.light()
                        } label: {
                            DirectoryCard(entry: entry, kind: kind)
                        }
                        .buttonStyle(CollectionPressStyle())
                    }
                }
            }
            .padding(.horizontal, AppPageLayout.horizontalInset)
            .padding(.top, AppPageLayout.topInset)
            .padding(.bottom, 16)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .appPageBackground()
        .appNavigationTitle(kind.title)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: {
                        ToolbarActionIcon("添加\(kind.title)", systemImage: "plus")
                    }
                }
            }
        }
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { entry in
            DirectoryEntrySheet(entry: entry, kind: kind, store: store, canEdit: canEdit)
        }
        .sheet(isPresented: $isAdding) {
            DirectoryEditor(store: store, kind: kind)
        }
        .accessibilityIdentifier("directory-\(kind.rawValue)")
    }
}

private struct DirectoryCard: View {
    let entry: SiteDirectoryEntry
    let kind: DirectoryKind
    @Environment(\.dynamicTypeSize) private var typeSize
    private let cardRadius: CGFloat = 19
    private let cardInset: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if kind == .friends {
                DirectoryArtwork(entry: entry, kind: kind)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            } else {
                DirectoryArtwork(entry: entry, kind: kind)
                    .frame(height: 82)
                    .clipShape(.rect(cornerRadius: cardRadius - cardInset))
            }
            Text(entry.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Text(entry.description.isEmpty ? (entry.destination?.host ?? "") : entry.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .padding(cardInset)
        .frame(maxWidth: .infinity, minHeight: kind == .friends ? 120 : 150, alignment: .topLeading)
        .plannerSurface(tint: Color.appAccent.opacity(0.06), radius: cardRadius)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct DirectoryEntrySheet: View {
    let kind: DirectoryKind
    let store: SiteDirectoryStore
    let canEdit: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var entry: SiteDirectoryEntry
    @State private var isEditing = false

    init(entry: SiteDirectoryEntry, kind: DirectoryKind, store: SiteDirectoryStore, canEdit: Bool) {
        _entry = State(initialValue: entry)
        self.kind = kind
        self.store = store
        self.canEdit = canEdit
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(entry.title).appContentTitle()
                    if kind == .friends {
                        DirectoryArtwork(entry: entry, kind: kind)
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                    } else {
                        DirectoryArtwork(entry: entry, kind: kind)
                            .frame(height: 180)
                            .clipShape(.rect(cornerRadius: 16))
                    }
                    if !entry.description.isEmpty {
                        Text(entry.description).foregroundStyle(.secondary)
                    }
                    if let tags = entry.tags, !tags.isEmpty {
                        Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    if let destination = entry.destination {
                        Link(destination: destination) {
                            Label(kind == .projects ? "打开项目" : "拜访网站", systemImage: "arrow.up.right")
                        }
                        .contentActionStyle(.prominent, size: .large)
                    }
                }
                .padding(.horizontal, AppPageLayout.horizontalInset)
                .padding(.top, AppPageLayout.topInset)
                .padding(.bottom, 20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .appPageBackground()
            .appNavigationTitle(kind.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { ToolbarActionIcon("关闭", systemImage: "xmark") }
                }
                if canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isEditing = true } label: { ToolbarActionIcon("编辑\(kind.title)", systemImage: "pencil") }
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            DirectoryEditor(store: store, kind: kind, original: entry) { entry = $0 }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct DirectoryArtwork: View {
    let entry: SiteDirectoryEntry
    let kind: DirectoryKind

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.appAccent.opacity(0.09)
                if let url = entry.imageURL {
                    if url.pathExtension.lowercased() == "svg" {
                        DirectorySVG(url: url) { placeholder }
                    } else {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .aspectRatio(contentMode: kind == .friends ? .fit : .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                            } else {
                                placeholder
                            }
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Group {
            if kind == .friends, let first = entry.title.first {
                Text(String(first).uppercased())
            } else {
                Image(systemName: kind.symbol)
            }
        }
        .font(.headline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct DirectorySVG<Placeholder: View>: View {
    let url: URL
    @ViewBuilder let placeholder: Placeholder
    @State private var svg: Data?

    var body: some View {
        Group {
            if let svg {
                SVGImageView(data: svg)
                    .id(url)
                    .allowsHitTesting(false)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            svg = nil
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let status = (response as? HTTPURLResponse)?.statusCode,
                      (200..<300).contains(status), data.count <= 1_048_576,
                      let text = String(data: data, encoding: .utf8),
                      text.contains("<svg") else { return }
                try Task.checkCancellation()
                svg = data
            } catch { }
        }
    }
}

private struct SVGImageView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.loadHTMLString("""
            <!doctype html>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
            <style>html,body{margin:0;width:100%;height:100%}img{display:block;width:100%;height:100%;object-fit:contain}</style>
            <img alt="" src="data:image/svg+xml;base64,\(data.base64EncodedString())">
            """, baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
