import SwiftUI

@MainActor
struct CollectionsScreen: View {
    let blog: BlogStore
    let photos: PhotoLibraryStore
    let library: ContentLibraryStore
    let dashboard: DashboardStore
    let account: AccountStore
    let open: (SiteSection) -> Void
    let showAccount: () -> Void
    let showStudio: () -> Void
    @State private var directory: SiteDirectoryStore
    @State private var screenshotDestination: DirectoryKind?

    init(blog: BlogStore, photos: PhotoLibraryStore, library: ContentLibraryStore,
         dashboard: DashboardStore, account: AccountStore, repository: GitHubRepository,
         open: @escaping (SiteSection) -> Void,
         showAccount: @escaping () -> Void, showStudio: @escaping () -> Void) {
        self.blog = blog
        self.photos = photos
        self.library = library
        self.dashboard = dashboard
        self.account = account
        self.open = open
        self.showAccount = showAccount
        self.showStudio = showStudio
        _directory = State(initialValue: SiteDirectoryStore(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                profileHeader
                activitySection
                destinationList
                if let latest = blog.posts.first {
                    latestBlog(latest)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 28)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("发布与同步", systemImage: "tray.and.arrow.up", action: showStudio)
                    Button("个人中心", systemImage: "person.crop.circle", action: showAccount)
                } label: {
                    Label("更多", systemImage: "ellipsis")
                }
            }
        }
        .task {
            await blog.loadIfNeeded()
            await directory.refresh()
            if dashboard.lastRefreshedAt == nil { await dashboard.refresh() }
        }
        .refreshable {
            await blog.refresh()
            await directory.refresh()
            await photos.refresh()
            await dashboard.refresh()
            library.syncPhotos(photos.photos, authoritative: photos.hasRemoteSnapshot)
        }
        #if DEBUG
        .navigationDestination(item: $screenshotDestination) { kind in
            SiteDirectoryScreen(store: directory, kind: kind)
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--projects") { screenshotDestination = .projects }
            if arguments.contains("--friends") { screenshotDestination = .friends }
        }
        #endif
    }

    // MARK: - Identity

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                avatarButton

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("@\(GitHubRepository.owner)")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)
            }

            HStack(spacing: 18) {
                Link(destination: DashboardService.websiteURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .semibold))
                        Text("mmddskq.top")
                            .font(.system(size: 15, weight: .medium))
                        Circle()
                            .fill(websiteStatusColor)
                            .frame(width: 6, height: 6)
                    }
                    .foregroundStyle(Color.appAccent)
                }

                Link(destination: DashboardService.profileURL) {
                    HStack(spacing: 6) {
                        Image("GitHubMark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                        Text("@\(GitHubRepository.owner)")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4)
        }
    }

    private var displayName: String {
        account.name.isEmpty ? "栖页" : account.name
    }

    private var websiteStatusColor: Color {
        guard let health = dashboard.website.value else { return Color.primary.opacity(0.2) }
        return health.isReachable ? Color.appAccent : Color.orange
    }

    private var avatarButton: some View {
        Button {
            Haptics.light()
            showAccount()
        } label: {
            ZStack {
                Circle().fill(Color.appSurface)
                if let url = account.avatarURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        monogram
                    }
                } else {
                    monogram
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(.circle)
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("个人中心")
        .accessibilityHint(account.isSignedIn ? "查看账号与设置" : "登录 GitHub")
    }

    private var monogram: some View {
        Text("栖")
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(Color.appAccent)
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 5) {
                    Text(contributionTotal)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.appAccent)
                    Text("次贡献 · 过去一年")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 8)

                Button {
                    Haptics.light()
                    showStudio()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background {
                            Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("发布与同步")
            }

            if let calendar = dashboard.contributions.value {
                HomeActivityGrid(calendar: calendar)
                activityFooter(calendar)
            } else if dashboard.contributions.isLoading {
                activityPlaceholder
            } else if let error = dashboard.contributions.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var contributionTotal: String {
        guard let total = dashboard.contributions.value?.total else { return "—" }
        return total.formatted()
    }

    private var activityPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .frame(height: 115)
            .overlay { ProgressView().controlSize(.small) }
            .accessibilityLabel("正在读取贡献")
    }

    private func activityFooter(_ calendar: DashboardContributions) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let recent = recentContributionCount(calendar) {
                Text("本周").foregroundStyle(.secondary)
                Text("\(recent)").foregroundStyle(Color.appAccent).fontWeight(.semibold)
                Text("次").foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if streakDays(calendar) > 0 {
                Text("连续")
                    .foregroundStyle(.secondary)
                Text("\(streakDays(calendar))")
                    .foregroundStyle(Color.appAccent)
                    .fontWeight(.semibold)
                Text("天")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 14))
        .accessibilityElement(children: .combine)
    }

    private func recentContributionCount(_ calendar: DashboardContributions) -> Int? {
        let counts = calendar.days.suffix(7).compactMap(\.count)
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    private func streakDays(_ calendar: DashboardContributions) -> Int {
        var days = calendar.days
        if let last = days.last, (last.count ?? 0) == 0 { days.removeLast() }
        return days.reversed().prefix { ($0.count ?? 0) > 0 }.count
    }

    // MARK: - Destinations

    private var destinationList: some View {
        VStack(spacing: 0) {
            Button { open(.photos) } label: {
                destinationRowLabel("图片", symbol: "photo.on.rectangle", detail: "\(photos.photos.count) 张")
            }
            .accessibilityIdentifier("collection-photos")

            rowDivider

            Button { open(.talks) } label: {
                destinationRowLabel("说说", symbol: "text.bubble", detail: "\(library.allTalks().count) 条")
            }

            rowDivider

            NavigationLink {
                SiteDirectoryScreen(store: directory, kind: .projects)
            } label: {
                destinationRowLabel("项目", symbol: "square.stack.3d.up", detail: "\(directory.projects.count) 个")
            }
            .accessibilityIdentifier("collection-projects")

            rowDivider

            NavigationLink {
                SiteDirectoryScreen(store: directory, kind: .friends)
            } label: {
                destinationRowLabel("友链", symbol: "person.2", detail: "\(directory.friends.count) 个")
            }
            .accessibilityIdentifier("collection-friends")
        }
        .background(Color.appSurface, in: .rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        }
        .buttonStyle(CollectionPressStyle())
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 70)
    }

    private func destinationRowLabel(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 40, height: 40)
                .background(Color.appAccent.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(detail)
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Latest post

    private func latestBlog(_ post: BlogPost) -> some View {
        NavigationLink {
            BlogDetailScreen(post: post)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "doc.text")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 40, height: 40)
                    .background(Color.appAccent.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("最新博客")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                    Text(post.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if post.date != .distantPast {
                        Text(post.date, format: .dateTime.year().month().day())
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSurface, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            }
            .contentShape(.rect)
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .combine)
            .accessibilityHint("打开全文")
        }
        .buttonStyle(CollectionPressStyle())
    }
}

// MARK: - Contribution heat map

private struct HomeActivityGrid: View {
    let calendar: DashboardContributions
    private let tile: CGFloat = 13
    private let gap: CGFloat = 4

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(calendar.weeks) { week in
                    VStack(spacing: gap) {
                        ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(day.map { fill(for: $0) } ?? .clear)
                                .frame(width: tile, height: tile)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .defaultScrollAnchor(.trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("贡献热力图，最近一年共 \(calendar.total ?? 0) 次")
    }

    private func fill(for day: DashboardContributionDay) -> Color {
        switch day.level {
        case 0: return Color.primary.opacity(0.07)
        case 1: return Color.appAccent.opacity(0.3)
        case 2: return Color.appAccent.opacity(0.5)
        case 3: return Color.appAccent.opacity(0.74)
        default: return Color.appAccent
        }
    }
}
