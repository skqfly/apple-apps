import SwiftUI

struct HomeScreen: View {
    let store: DashboardStore
    let pending: PendingChangesStore
    let repository: GitHubRepository
    let canPush: Bool
    @State private var pushMessage: String?
    @State private var showsPushResult = false
    @State private var showsPendingPushResult = false
    @State private var showsPendingDetails = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pendingCard
                websiteCard
                contributionsCard
                workflowsCard
                refreshStatus
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(DashboardStyle.background(colorScheme))
        .tint(DashboardStyle.accent(colorScheme))
        .sheet(isPresented: $showsPendingDetails) {
            pendingDetails
                .tint(DashboardStyle.accent(colorScheme))
        }
        .navigationTitle("首页")
        .task {
            if store.lastRefreshedAt == nil { await store.refresh() }
        }
        .refreshable { await store.refresh() }
        .alert("推送结果", isPresented: $showsPushResult) {
            Button("好", role: .cancel) { }
        } message: { Text(pushMessage ?? "") }
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    pendingSummary
                    Spacer(minLength: 0)
                    pushButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    pendingSummary
                    pushButton
                }
            }
            if let error = pending.error {
                DashboardErrorNote(message: error)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(DashboardStyle.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(DashboardStyle.outline(colorScheme).opacity(0.7), lineWidth: 0.75)
        }
    }

    private var pendingSummary: some View {
        Button { showsPendingDetails = true } label: {
            HStack(spacing: 10) {
                Image(systemName: pending.changes.isEmpty ? "checkmark.circle" : "tray.and.arrow.up")
                    .foregroundStyle(DashboardStyle.accent(colorScheme))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.changes.isEmpty ? "暂无待推送" : "\(pending.changes.count) 项待推送")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(canPush ? "查看暂存详情" : "登录 GitHub 后推送")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开详情，查看或逐项撤销待推送操作")
    }

    private var pushButton: some View {
        Button { Task { await push() } } label: {
            HStack(spacing: 6) {
                if pending.isCommitting {
                    ProgressView().controlSize(.small)
                    Text("推送中…")
                } else {
                    Label("推送", systemImage: "arrow.up")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 4)
            .frame(minHeight: 32)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(.rect(cornerRadius: 11))
        .disabled(pending.isCommitting || pending.changes.isEmpty || !canPush)
        .accessibilityLabel(pending.isCommitting ? "正在推送" : "推送全部 \(pending.changes.count) 项改动")
    }

    private var pendingDetails: some View {
        NavigationStack {
            List {
                Section {
                    if pending.changes.isEmpty {
                        Label("暂无待推送的改动", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pending.changes) { change in
                            let layout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                            layout {
                                Image(systemName: changeSymbol(change))
                                    .foregroundStyle(DashboardStyle.accent(colorScheme))
                                    .frame(minHeight: 44)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(change.kind.label).font(.subheadline.weight(.semibold))
                                    Text(changeSummary(change))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 8)
                                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                                Button("撤销") { pending.remove(change) }
                                    .font(.subheadline)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .buttonStyle(.borderless)
                                    .disabled(pending.isCommitting)
                                    .accessibilityLabel("撤销\(change.kind.label)，\(changeSummary(change))")
                            }
                        }
                    }
                } header: {
                    Text("\(pending.changes.count) 项暂存操作")
                } footer: {
                    Text("改动暂存在本机，推送后才会提交到 GitHub。")
                }
                Section {
                    pushButton
                    if let error = pending.error { DashboardErrorNote(message: error) }
                    if !canPush {
                        Text("在个人中心登录 GitHub 后即可推送。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("待推送变更")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .alert("推送结果", isPresented: $showsPendingPushResult) {
            Button("好", role: .cancel) { }
        } message: { Text(pushMessage ?? "") }
    }

    private func changeSummary(_ change: PendingChange) -> String {
        switch change.kind {
        case .addPhoto(_, _, _, _, _, let alt):
            return alt.isEmpty ? "新照片" : alt
        case .deletePhoto(let id, _), .unpublishPhoto(let id, _):
            return id
        case .reorderPhotos(let ids):
            return "\(ids.count) 张已发表照片"
        case .addTalk(_, let text, _, _, _), .editTalk(_, let text, _, _, _):
            return text.isEmpty ? "图片说说" : String(text.prefix(100))
        case .unpublishTalk(let id), .deleteTalk(let id, _):
            return id
        }
    }

    private func changeSymbol(_ change: PendingChange) -> String {
        switch change.kind {
        case .addPhoto, .addTalk: return "plus.circle.fill"
        case .editTalk: return "pencil.circle.fill"
        case .unpublishPhoto, .unpublishTalk: return "arrow.down.circle.fill"
        case .deletePhoto, .deleteTalk: return "trash.fill"
        case .reorderPhotos: return "arrow.up.arrow.down.circle.fill"
        }
    }

    private func push() async {
        do {
            let sha = try await pending.commitAll(repository: repository)
            pushMessage = "已推送到 GitHub（提交 \(String(sha.prefix(7)))）。网站部署完成后即可见。"
            await store.refresh()
        } catch {
            pushMessage = error.localizedDescription
        }
        if showsPendingDetails {
            showsPendingPushResult = true
        } else {
            showsPushResult = true
        }
    }

    private var refreshStatus: some View {
        HStack(spacing: 8) {
            if store.isRefreshing {
                Text("正在更新状态…")
            } else if let date = store.lastRefreshedAt {
                Text("最近检查")
                Text(date, style: .relative)
            } else {
                Text("下拉刷新网站与 GitHub 状态")
            }
            Spacer(minLength: 4)
            Button {
                Task { await store.refresh() }
            } label: {
                Label("刷新状态", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(store.isRefreshing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var websiteCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    websiteLink
                    Spacer(minLength: 0)
                    websiteSummary
                }
                VStack(alignment: .leading, spacing: 4) {
                    websiteLink
                    websiteSummary
                }
            }
            if let error = store.website.error {
                DashboardErrorNote(message: error, showsPrevious: store.website.value != nil)
                if let health = store.website.value {
                    Text("上次检测：\(health.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.isConnected {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        repositoryDetails
                        pagesDetails
                    }
                    .padding(.vertical, 8)
                } label: {
                    HStack(spacing: 6) {
                        Text("仓库与部署")
                        if let pages = store.pages.value {
                            Text("· \(pages.statusLabel)").foregroundStyle(.secondary)
                        }
                        if store.repository.isLoading || store.pages.isLoading {
                            ProgressView().controlSize(.mini)
                        } else if store.repository.error != nil || store.pages.error != nil {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("仓库或部署状态读取失败，展开查看")
                        }
                    }
                    .font(.caption)
                    .frame(minHeight: 44, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var websiteLink: some View {
        Link(destination: DashboardService.websiteURL) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(DashboardStyle.accent(colorScheme))
                Text("mmddskq.top").font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.up.right").font(.caption)
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityLabel("网站状态，打开 mmddskq.top")
    }

    @ViewBuilder private var websiteSummary: some View {
        if let health = store.website.value {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { healthSummary(health) }
                VStack(alignment: .leading, spacing: 4) { healthSummary(health) }
            }
        } else if store.website.isLoading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("检测中…").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Label("状态未确认", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func healthSummary(_ health: WebsiteHealth) -> some View {
        Label(health.isReachable ? "可访问" : "响应异常", systemImage: health.isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(health.isReachable ? DashboardStyle.accent(colorScheme) : Color.orange)
        Text("HTTP \(health.statusCode) · \((health.duration * 1_000).formatted(.number.precision(.fractionLength(0)))) ms")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var repositoryDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let repo = store.repository.value {
                Link(destination: repo.htmlURL) {
                    Label("\(repo.defaultBranch) · 仓库", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.subheadline)
                        .frame(minHeight: 32, alignment: .leading)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("仓库更新")
                    Spacer()
                    Text(repo.updatedAt, style: .relative)
                }
                .font(.caption).foregroundStyle(.secondary)
                if let pushed = repo.pushedAt {
                    HStack(alignment: .firstTextBaseline) {
                        Text("最近推送")
                        Spacer()
                        Text(pushed, style: .relative)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            } else if store.repository.isLoading {
                loading("正在读取仓库信息…")
            }
            if let error = store.repository.error {
                DashboardErrorNote(message: error, showsPrevious: store.repository.value != nil)
            }
        }
    }

    private var pagesDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pages = store.pages.value {
                HStack(alignment: .firstTextBaseline) {
                    Text("GitHub Pages")
                    Spacer()
                    Text(pages.statusLabel)
                }
                .font(.caption).foregroundStyle(.secondary)
                if let branch = pages.source?.branch {
                    Text("Pages 来源分支：\(branch)").font(.caption).foregroundStyle(.secondary)
                }
                if let url = pages.htmlURL {
                    Link("查看 Pages 网站", destination: url).font(.caption)
                }
            } else if store.pages.isLoading {
                loading("正在读取 Pages 构建信息…")
            }
            if let error = store.pages.error {
                DashboardErrorNote(message: error, showsPrevious: store.pages.value != nil)
            }
        }
    }

    private var workflowsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("Actions", systemImage: "play.circle")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if store.workflows.isLoading {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在更新 Actions")
                }
                Spacer(minLength: 0)
                Link("全部运行", destination: DashboardService.actionsURL)
                    .font(.caption)
                    .frame(minHeight: 44)
            }
            if !store.isConnected {
                Label("登录 GitHub，查看工作流实时状态。", systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            if let runs = store.workflows.value {
                if runs.isEmpty {
                    Label("暂无工作流运行记录", systemImage: "tray")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(runs) { run in
                        if run.id != runs.first?.id { Divider() }
                        DashboardWorkflowRow(run: run)
                    }
                }
            } else if store.workflows.isLoading {
                loading("正在读取最近的运行记录…")
            }
            if let error = store.workflows.error {
                DashboardErrorNote(message: error, showsPrevious: store.workflows.value != nil)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var contributionsCard: some View {
        if let calendar = store.contributions.value {
            VStack(alignment: .leading, spacing: 8) {
                ContributionCalendarView(calendar: calendar, isLoading: store.contributions.isLoading)
                if let error = store.contributions.error {
                    DashboardErrorNote(message: error, showsPrevious: true)
                        .padding(.horizontal, 4)
                }
            }
        } else {
            DashboardCard(title: "贡献", symbol: "chart.dots.scatter", isLoading: store.contributions.isLoading) {
                if store.contributions.isLoading {
                    loading("正在读取贡献日历…")
                }
                if let error = store.contributions.error {
                    DashboardErrorNote(message: error)
                }
                Link("在 GitHub 查看 skqfly", destination: DashboardService.profileURL)
                    .font(.caption)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    private func loading(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
