import Foundation
import Observation

@Observable @MainActor
final class DashboardStore {
    private(set) var website = DashboardResource<WebsiteHealth>()
    private(set) var repository = DashboardResource<DashboardRepository>()
    private(set) var workflows = DashboardResource<[DashboardWorkflowRun]>()
    private(set) var pages = DashboardResource<DashboardPages>()
    private(set) var contributions = DashboardResource<DashboardContributions>()
    private(set) var lastRefreshedAt: Date?
    var isConnected: Bool { token != nil }

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var tokenRefresh: Task<Void, Never>?
    @ObservationIgnored private let service = DashboardService()

    init() {}

    var isRefreshing: Bool {
        website.isLoading || repository.isLoading || workflows.isLoading || pages.isLoading || contributions.isLoading
    }

    /// The token is kept in memory only. Pass nil on sign out.
    /// Changing credentials refreshes all resources and invalidates older responses.
    func updateToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        guard self.token != next else { return }
        self.token = next
        revision += 1
        tokenRefresh?.cancel()
        // Remove data fetched under the old authorization before reloading.
        website = .init()
        repository = .init()
        workflows = .init()
        pages = .init()
        contributions = .init()
        lastRefreshedAt = nil
        tokenRefresh = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
        }
    }

    func refresh() async {
        revision += 1
        let requestRevision = revision
        let requestToken = token
        website.isLoading = true
        repository.isLoading = requestToken != nil
        workflows.isLoading = requestToken != nil
        pages.isLoading = requestToken != nil
        contributions.isLoading = true
        async let site: Void = loadWebsite(revision: requestRevision)
        async let repo: Void = loadRepository(token: requestToken, revision: requestRevision)
        async let runs: Void = loadWorkflows(token: requestToken, revision: requestRevision)
        async let deployment: Void = loadPages(token: requestToken, revision: requestRevision)
        async let calendar: Void = loadContributions(token: requestToken, revision: requestRevision)
        _ = await (site, repo, runs, deployment, calendar)
        guard revision == requestRevision, !Task.isCancelled else { return }
        lastRefreshedAt = .now
    }

    private func loadWebsite(revision: Int) async {
        let result = await fetch(previous: website) { [service] in try await service.website() }
        if self.revision == revision { website = result }
    }

    private func loadRepository(token: String?, revision: Int) async {
        guard token != nil else { return }
        let result = await fetch(previous: repository) { [service] in try await service.repository(token: token) }
        if self.revision == revision { repository = result }
    }

    private func loadWorkflows(token: String?, revision: Int) async {
        guard token != nil else { return }
        let result = await fetch(previous: workflows) { [service] in try await service.workflows(token: token) }
        if self.revision == revision { workflows = result }
    }

    private func loadPages(token: String?, revision: Int) async {
        guard token != nil else { return }
        let result = await fetch(previous: pages) { [service] in try await service.pages(token: token) }
        if self.revision == revision { pages = result }
    }

    private func loadContributions(token: String?, revision: Int) async {
        let result = await fetch(previous: contributions) { [service] in try await service.contributions(token: token) }
        if self.revision == revision { contributions = result }
    }

    private func fetch<Value: Sendable>(
        previous: DashboardResource<Value>,
        operation: @Sendable () async throws -> Value
    ) async -> DashboardResource<Value> {
        var result = previous
        do {
            result.value = try await operation()
            result.error = nil
            result.updatedAt = .now
        } catch is CancellationError {
            // A cancelled screen task should not present a connection error.
        } catch {
            if !Task.isCancelled { result.error = DashboardService.message(for: error) }
        }
        result.isLoading = false
        return result
    }
}
