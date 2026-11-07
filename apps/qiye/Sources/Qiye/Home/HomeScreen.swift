import SwiftUI

struct HomeScreen: View {
    let store: DashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                refreshStatus
                websiteCard
                contributionsCard
                workflowsCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.appBackground)
        .tint(.appAccent)
        .navigationTitle("首页")
        .task {
            if store.lastRefreshedAt == nil { await store.refresh() }
        }
        .refreshable { await store.refresh() }
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
        DashboardCard(title: "网站状态", symbol: "globe", isLoading: store.website.isLoading || store.repository.isLoading || store.pages.isLoading) {
            VStack(alignment: .leading, spacing: 16) {
                Link(destination: DashboardService.websiteURL) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("mmddskq.top").font(.title3.weight(.semibold))
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                }
                if let health = store.website.value {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) { healthSummary(health) }
                        VStack(alignment: .leading, spacing: 8) { healthSummary(health) }
                    }
                    if store.website.error != nil {
                        Text("上次检测：\(health.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if store.website.isLoading {
                    loading("正在检测网站 HTTP 状态…")
                } else {
                    Label("尚无法确认网站状态", systemImage: "questionmark.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let error = store.website.error {
                    DashboardErrorNote(message: error, showsPrevious: store.website.value != nil)
                }
                if store.isConnected {
                    Divider()
                    repositoryDetails
                    pagesDetails
                }
            }
        }
    }

    @ViewBuilder private func healthSummary(_ health: WebsiteHealth) -> some View {
        Label(health.isReachable ? "可访问" : "响应异常", systemImage: health.isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(health.isReachable ? Color.green : Color.orange)
        HStack(spacing: 10) {
            Text("HTTP \(health.statusCode)")
            Text(health.duration * 1_000, format: .number.precision(.fractionLength(0))) + Text(" ms")
        }
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
        DashboardCard(title: "GitHub Actions", symbol: "play.circle", isLoading: store.workflows.isLoading) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("最近 5 次运行").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Link("全部运行", destination: DashboardService.actionsURL).font(.caption)
                }
                if !store.isConnected {
                    Label("在右上角连接 GitHub，查看工作流的实时状态。", systemImage: "person.crop.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let runs = store.workflows.value {
                    if runs.isEmpty {
                        Label("仓库暂无工作流运行记录", systemImage: "tray")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(runs) { run in
                            if run.id != runs.first?.id { Divider() }
                            DashboardWorkflowRow(run: run)
                        }
                    }
                } else if store.workflows.isLoading {
                    loading("正在读取工作流运行记录…")
                }
                if let error = store.workflows.error {
                    DashboardErrorNote(message: error, showsPrevious: store.workflows.value != nil)
                }
            }
        }
    }

    private var contributionsCard: some View {
        DashboardCard(title: "GitHub 贡献", symbol: "square.grid.3x3", isLoading: store.contributions.isLoading) {
            VStack(alignment: .leading, spacing: 16) {
                if let calendar = store.contributions.value {
                    ContributionCalendarView(calendar: calendar)
                } else if store.contributions.isLoading {
                    loading("正在读取近一年的贡献日历…")
                }
                if let error = store.contributions.error {
                    DashboardErrorNote(message: error, showsPrevious: store.contributions.value != nil)
                }
                Link("在 GitHub 查看 skqfly", destination: DashboardService.profileURL)
                    .font(.caption)
                    .frame(minHeight: 32, alignment: .leading)
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
