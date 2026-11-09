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
    @State private var showsWebsiteDetails = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var canClickPush: Bool {
        !pending.isCommitting && !pending.changes.isEmpty && canPush
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Top status chip (Refined, un-tinted, concise)
                statusSummaryBar

                // Activity (English GitHub Calendar card matching reference)
                contributionsCard

                // Actions (Workflow runs)
                workflowsCard

                refreshStatus
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 96)
        }
        .background(Color.appBackground)
        .navigationTitle("主页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                headerActionButtons
            }
        }
        .sheet(isPresented: $showsPendingDetails) {
            pendingDetails
        }
        .sheet(isPresented: $showsWebsiteDetails) {
            websiteDetailsSheet
        }
        .task {
            if store.lastRefreshedAt == nil { await store.refresh() }
        }
        .refreshable { await store.refresh() }
        .alert("推送结果", isPresented: $showsPushResult) {
            Button("好", role: .cancel) { }
        } message: { Text(pushMessage ?? "") }
    }

    // MARK: - Navigation Bar Right Actions (Two Independent Liquid Glass Circles, Pure and Un-nested)

    private var headerActionButtons: some View {
        HStack(spacing: 8) {
            // Website button
            Button {
                Haptics.light()
                showsWebsiteDetails = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                    if let health = store.website.value {
                        Circle()
                            .fill(health.isReachable ? Color(red: 0.16, green: 0.65, blue: 0.45) : Color.orange)
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .buttonStyle(AppleNavCircleButtonStyle(size: 34))
            .accessibilityLabel("网站状态与仓库")

            // Staging & Push button
            Button {
                Haptics.light()
                showsPendingDetails = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: pending.changes.isEmpty ? "tray" : "tray.and.arrow.up.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pending.changes.isEmpty ? Color.primary : Color.appAccent)
                    if !pending.changes.isEmpty {
                        Circle()
                            .fill(Color.appAccent)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -2)
                    }
                }
            }
            .buttonStyle(AppleNavCircleButtonStyle(size: 34, isAccent: !pending.changes.isEmpty))
            .accessibilityLabel("待推送改动，\(pending.changes.count) 项")
        }
    }

    // MARK: - Refined Status Summary Bar (Un-tinted, Elegant)

    private var statusSummaryBar: some View {
        HStack(spacing: 8) {
            // Website indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(websiteStatusColor)
                    .frame(width: 7, height: 7)

                Link("mmddskq.top", destination: DashboardService.websiteURL)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Response time or state
            if let health = store.website.value {
                Text("\(Int(health.duration * 1_000)) ms")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if store.website.isLoading {
                Text("检测中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Deployment status tag
            if let pages = store.pages.value {
                Text(pages.statusLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlassCard(cornerRadius: 14)
    }

    private var websiteStatusColor: Color {
        if let health = store.website.value {
            return health.isReachable ? Color(red: 0.16, green: 0.65, blue: 0.45) : Color.orange
        }
        return Color.secondary
    }

    // MARK: - Contributions Card

    @ViewBuilder
    private var contributionsCard: some View {
        if let calendar = store.contributions.value {
            ContributionCalendarView(calendar: calendar, isLoading: store.contributions.isLoading)
        } else {
            DashboardCard(title: "Activity", symbol: "github-mark", isLoading: store.contributions.isLoading) {
                if store.contributions.isLoading {
                    loading("Loading GitHub activity…")
                }
                if let error = store.contributions.error {
                    DashboardErrorNote(message: error)
                }
                Link("View skqfly on GitHub", destination: DashboardService.profileURL)
                    .font(.caption)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    // MARK: - Actions Card

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
                    .foregroundStyle(Color.appAccent)
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
        .padding(14)
        .liquidGlassCard(cornerRadius: 18)
    }

    // MARK: - Refresh Status

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
                Haptics.light()
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

    // MARK: - Pending Details Sheet

    private var pendingDetails: some View {
        NavigationStack {
            List {
                Section {
                    if pending.changes.isEmpty {
                        Label("暂无待推送的改动", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pending.changes) { change in
                            pendingRow(change)
                        }
                    }
                } header: {
                    Text("\(pending.changes.count) 项暂存操作")
                } footer: {
                    Text("改动暂存在本机，点击下方推送即可提交到 GitHub。")
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showsPendingDetails = false }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .alert("推送结果", isPresented: $showsPendingPushResult) {
            Button("好", role: .cancel) { }
        } message: { Text(pushMessage ?? "") }
    }

    private func pendingRow(_ change: PendingChange) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            Image(systemName: changeSymbol(change))
                .foregroundStyle(Color.appAccent)
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

    // High-contrast, clear Push Button
    private var pushButton: some View {
        Button {
            Haptics.medium()
            Task { await push() }
        } label: {
            HStack {
                Spacer()
                if pending.isCommitting {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("正在推送…")
                } else {
                    Label("推送全部更改", systemImage: "arrow.up.circle.fill")
                }
                Spacer()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(canClickPush ? Color.white : Color.primary.opacity(0.35))
            .padding(.vertical, 12)
            .background(
                canClickPush
                    ? Color.appAccent
                    : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canClickPush)
        .accessibilityLabel(pending.isCommitting ? "正在推送" : "推送全部 \(pending.changes.count) 项改动")
    }

    // MARK: - Website Details Sheet

    private var websiteDetailsSheet: some View {
        NavigationStack {
            List {
                Section("网站与访问") {
                    Link(destination: DashboardService.websiteURL) {
                        HStack {
                            Label("mmddskq.top", systemImage: "globe")
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let health = store.website.value {
                        LabeledContent("状态", value: health.isReachable ? "正常可访问" : "响应异常")
                        LabeledContent("HTTP 响应码", value: "\(health.statusCode)")
                        LabeledContent("响应耗时", value: "\(Int(health.duration * 1000)) ms")
                        LabeledContent("上次检测", value: health.checkedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                if store.isConnected {
                    Section("仓库与部署") {
                        if let repo = store.repository.value {
                            Link(destination: repo.htmlURL) {
                                LabeledContent("仓库分支", value: "\(repo.defaultBranch)")
                            }
                            LabeledContent("最近推送", value: repo.pushedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")
                        }
                        if let pages = store.pages.value {
                            LabeledContent("Pages 状态", value: pages.statusLabel)
                            if let branch = pages.source?.branch {
                                LabeledContent("来源分支", value: branch)
                            }
                        }
                    }
                }
            }
            .navigationTitle("站点详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showsWebsiteDetails = false }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

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

    private func loading(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
