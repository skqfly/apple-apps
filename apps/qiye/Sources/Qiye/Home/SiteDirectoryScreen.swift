import SwiftUI

enum DirectoryKind: String, Hashable {
    case projects, friends
    var title: String { self == .projects ? "项目" : "友链" }
}

struct SiteDirectoryEntry: Decodable, Identifiable {
    var id: String { url }
    let title: String
    let description: String
    let url: String
    let image: String?
    let tags: [String]?

    var destination: URL? {
        guard let value = URL(string: url), value.scheme == "https" || value.scheme == "http" else { return nil }
        return value
    }

    var imageURL: URL? {
        image.flatMap { URL(string: $0, relativeTo: DashboardService.websiteURL)?.absoluteURL }
    }
}

@Observable @MainActor
final class SiteDirectoryStore {
    private struct Site: Decodable {
        struct Projects: Decodable { let projects: [SiteDirectoryEntry] }
        struct Friends: Decodable { let friends: [SiteDirectoryEntry] }
        let projectsPageContent: Projects
        let friendsPageContent: Friends
    }

    private(set) var projects: [SiteDirectoryEntry] = []
    private(set) var friends: [SiteDirectoryEntry] = []
    private(set) var error: String?
    private(set) var isLoading = false
    private let repository: GitHubRepository

    init(repository: GitHubRepository) {
        self.repository = repository
        if let url = Bundle.main.url(forResource: "site", withExtension: "json"),
           let data = try? Data(contentsOf: url), let site = try? JSONDecoder().decode(Site.self, from: data) {
            projects = site.projectsPageContent.projects
            friends = site.friendsPageContent.friends
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await repository.getRepositoryFile(path: "src/data/site.json")
            let site = try JSONDecoder().decode(Site.self, from: data)
            projects = site.projectsPageContent.projects
            friends = site.friendsPageContent.friends
            error = nil
        } catch is CancellationError { }
        catch { self.error = "暂时无法更新，正在显示已保存的内容。" }
    }
}

@MainActor
struct SiteDirectoryScreen: View {
    let store: SiteDirectoryStore
    let kind: DirectoryKind
    @State private var query = ""
    @State private var selected: SiteDirectoryEntry?

    private var entries: [SiteDirectoryEntry] {
        let all = kind == .projects ? store.projects : store.friends
        return all.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.description.localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                CollectionSearchField(text: $query, prompt: "搜索\(kind.title)")
                if let error = store.error {
                    ContentStatus(message: error) { await store.refresh() }
                }
                if entries.isEmpty {
                    ContentUnavailableView("暂无\(kind.title)", systemImage: kind == .projects ? "square.stack.3d.up" : "person.2")
                }
                ForEach(entries) { entry in
                    Button { selected = entry; Haptics.light() } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack {
                                CollectionArtwork(name: kind == .projects ? "glassCabinet" : "sunlitWalk")
                                if let imageURL = entry.imageURL {
                                    AsyncImage(url: imageURL) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                    }
                                }
                            }
                            .frame(height: kind == .projects ? 190 : 140).clipped()
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.title).font(.title3.weight(.semibold))
                                    Text(entry.description).font(.subheadline).foregroundStyle(.secondary)
                                        .lineLimit(3).lineSpacing(3)
                                    if let host = entry.destination?.host {
                                        Text(host).font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                            }
                            .padding(18)
                        }
                        .collectionSurface().clipShape(.rect(cornerRadius: 22))
                        .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(CollectionPressStyle())
                }
            }
            .padding(18).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle(kind.title).navigationBarTitleDisplayMode(.large)
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { entry in DirectoryEntrySheet(entry: entry, kind: kind) }
        .accessibilityIdentifier("directory-\(kind.rawValue)")
    }
}

private struct DirectoryEntrySheet: View {
    let entry: SiteDirectoryEntry
    let kind: DirectoryKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                CollectionArtwork(name: kind == .projects ? "glassCabinet" : "sunlitWalk")
                    .frame(height: 220).clipShape(.rect(cornerRadius: 22))
                Text(entry.title).font(.largeTitle.bold())
                Text(entry.description).font(.body).foregroundStyle(.secondary).lineSpacing(6)
                if let tags = entry.tags, !tags.isEmpty {
                    Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                if let destination = entry.destination {
                    Link(destination: destination) {
                        HStack {
                            Text(kind == .projects ? "查看项目" : "拜访网站")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.headline).padding(18)
                        .foregroundStyle(Color.appBackground)
                        .background(Color.primary, in: Capsule())
                    }
                }
            }
            .padding(24).padding(.top, 24)
        }
        .background(Color.appBackground)
        .overlay(alignment: .topTrailing) {
            Button("关闭", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly).buttonStyle(AppleNavCircleButtonStyle(size: 36)).padding(16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }
}
