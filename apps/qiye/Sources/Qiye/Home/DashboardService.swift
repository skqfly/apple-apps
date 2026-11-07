import Foundation

struct DashboardService: Sendable {
    static let websiteURL = URL(string: "https://mmddskq.top")!
    static let repositoryURL = URL(string: "https://github.com/skqfly/skqfly.github.io")!
    static let actionsURL = repositoryURL.appending(path: "actions")
    static let profileURL = URL(string: "https://github.com/skqfly")!
    private static let apiBase = "https://api.github.com/repos/skqfly/skqfly.github.io"

    func website() async throws -> WebsiteHealth {
        var request = URLRequest(url: Self.websiteURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let start = ContinuousClock.now
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let duration = start.duration(to: .now)
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return WebsiteHealth(statusCode: response.statusCode, duration: seconds, checkedAt: .now)
    }

    func repository(token: String?) async throws -> DashboardRepository {
        guard token != nil else { throw DashboardFailure.message("连接 GitHub 后可查看仓库更新和工作流。") }
        return try await get(Self.apiBase, token: token)
    }

    func workflows(token: String?) async throws -> [DashboardWorkflowRun] {
        guard token != nil else { throw DashboardFailure.message("连接 GitHub 后可查看最近工作流。") }
        struct Response: Decodable { let workflowRuns: [DashboardWorkflowRun]
            enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
        }
        let result: Response = try await get(Self.apiBase + "/actions/runs?per_page=5", token: token)
        return result.workflowRuns
    }

    func pages(token: String?) async throws -> DashboardPages {
        try await get(Self.apiBase + "/pages", token: token)
    }

    func contributions(token: String?) async throws -> DashboardContributions {
        let now = Date.now
        if let token {
            do {
                return try await graphQLContributions(token: token, now: now)
            } catch {
                try Task.checkCancellation()
                return try await publicContributions(now: now, notice: "授权贡献数据暂不可用，已显示 GitHub 公开贡献。")
            }
        }
        return try await publicContributions(now: now)
    }

    private func get<T: Decodable>(_ address: String, token: String?) async throws -> T {
        guard let url = URL(string: address) else { throw URLError(.badURL) }
        let data = try await data(for: request(url: url, token: token))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func request(url: URL, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Qiye-Dashboard", forHTTPHeaderField: "User-Agent")
        if url.host == "api.github.com" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        } else {
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        }
        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let code = response.statusCode
            if request.url?.path.hasSuffix("/pages") == true {
                throw DashboardFailure.message("Pages 信息不可用（HTTP \(code)），可能未开放权限或未配置。")
            }
            switch code {
            case 401: throw DashboardFailure.message("GitHub 授权失效，请在账户中更新令牌。")
            case 403, 429: throw DashboardFailure.message("GitHub 权限不足或请求受限（HTTP \(code)），请稍后重试。")
            case 404: throw DashboardFailure.message("GitHub 资源不可用（HTTP 404），请检查访问权限。")
            default: throw DashboardFailure.message("请求失败（HTTP \(code)），请稍后重试。")
            }
        }
        return data
    }

    private func graphQLContributions(token: String, now: Date) async throws -> DashboardContributions {
        let range = DashboardDates.range(now: now)
        let iso = ISO8601DateFormatter()
        let query = """
        query($from: DateTime!, $to: DateTime!) {
          user(login: "skqfly") {
            contributionsCollection(from: $from, to: $to) {
              contributionCalendar {
                weeks { contributionDays { date contributionCount contributionLevel } }
              }
            }
          }
        }
        """
        var request = request(url: URL(string: "https://api.github.com/graphql")!, token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": ["from": iso.string(from: range.start), "to": iso.string(from: now)]
        ])
        let payload = try await data(for: request)
        let response = try JSONDecoder().decode(ContributionGraphQLResponse.self, from: payload)
        guard response.errors?.isEmpty != false,
              let calendar = response.data?.user?.contributionsCollection.contributionCalendar else {
            throw DashboardFailure.message("GitHub 未提供授权贡献数据。")
        }
        let formatter = DashboardDates.dayFormatter()
        let levels = ["NONE": 0, "FIRST_QUARTILE": 1, "SECOND_QUARTILE": 2, "THIRD_QUARTILE": 3, "FOURTH_QUARTILE": 4]
        let days = try calendar.weeks.flatMap(\.contributionDays).map { day in
            guard let date = formatter.date(from: day.date), let level = levels[day.contributionLevel], day.contributionCount >= 0 else {
                throw DashboardFailure.message("GitHub 贡献数据格式已变更。")
            }
            return DashboardContributionDay(id: day.date, date: date, level: level, count: day.contributionCount)
        }.filter { $0.date >= range.start && $0.date <= range.end }
        try validateRange(days, range: range)
        return try DashboardContributions(days: days, source: .graphQL)
    }

    private func publicContributions(now: Date, notice: String? = nil) async throws -> DashboardContributions {
        let range = DashboardDates.range(now: now)
        // GitHub's default endpoint returns its rolling year. Supplying from/to
        // can select a calendar year instead, silently dropping earlier months.
        let url = URL(string: "https://github.com/users/skqfly/contributions")!
        let response = try await data(for: request(url: url))
        guard let html = String(data: response, encoding: .utf8) else {
            throw DashboardFailure.message("无法读取 GitHub 公开贡献页面。")
        }
        let days = try ContributionHTMLParser.parse(html).filter { $0.date >= range.start && $0.date <= range.end }
        try validateRange(days, range: range)
        return try DashboardContributions(days: days, source: .publicHTML, notice: notice)
    }

    private func validateRange(_ days: [DashboardContributionDay], range: (start: Date, end: Date)) throws {
        guard days.map(\.date).min() == range.start, days.map(\.date).max() == range.end else {
            throw DashboardFailure.message("GitHub 未返回完整的近一年贡献日历，请重试。")
        }
    }

    static func message(for error: Error) -> String {
        if let failure = error as? DashboardFailure { return failure.localizedDescription }
        if error is DecodingError { return "服务返回的数据格式无法识别，请稍后重试。" }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: return "网络连接不可用，请检查网络后重试。"
            case .timedOut: return "请求超时，请下拉刷新重试。"
            case .secureConnectionFailed, .serverCertificateUntrusted: return "无法建立安全连接，请稍后重试。"
            default: return "连接失败，请稍后重试。"
            }
        }
        return "暂时无法获取数据，请下拉刷新重试。"
    }
}

private struct ContributionGraphQLResponse: Decodable {
    struct GraphQLError: Decodable { let message: String }
    struct Payload: Decodable { let user: User? }
    struct User: Decodable { let contributionsCollection: Collection }
    struct Collection: Decodable { let contributionCalendar: ContributionCalendar }
    struct ContributionCalendar: Decodable { let weeks: [Week] }
    struct Week: Decodable { let contributionDays: [Day] }
    struct Day: Decodable {
        let date: String
        let contributionCount: Int
        let contributionLevel: String
    }
    let data: Payload?
    let errors: [GraphQLError]?
}

// Only GitHub's dated cells and explicitly associated English tooltip counts are accepted.
// Missing counts remain nil, even when the color level happens to be zero.
enum ContributionHTMLParser {
    static func parse(_ html: String) throws -> [DashboardContributionDay] {
        let tags = try matches(#"<(?:td|rect)\b[^>]*\bdata-date\s*=\s*[\"'][^\"']+[\"'][^>]*>"#, in: html)
        let tooltips = try matches(#"<tool-tip\b([^>]*)>([\s\S]*?)</tool-tip>"#, in: html)
        var counts: [String: Int] = [:]
        for match in tooltips {
            let attributes = try attributes(in: match[1])
            guard let id = attributes["for"] else { continue }
            let text = match[2].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("No contributions on ") { counts[id] = 0 }
            else if let countMatch = try matches(#"^([0-9]+(?:,[0-9]{3})*) contributions? on "#, in: text).first,
                    let count = Int(countMatch[1].replacingOccurrences(of: ",", with: "")) {
                counts[id] = count
            }
        }
        let formatter = DashboardDates.dayFormatter()
        let days = try tags.map { tag -> DashboardContributionDay in
            let attributes = try attributes(in: tag[0])
            guard let key = attributes["data-date"], let date = formatter.date(from: key),
                  let levelText = attributes["data-level"], let level = Int(levelText), (0...4).contains(level) else {
                throw DashboardFailure.message("GitHub 公开贡献页面格式已变更。")
            }
            return DashboardContributionDay(id: key, date: date, level: level, count: attributes["id"].flatMap { counts[$0] })
        }
        guard !days.isEmpty else { throw DashboardFailure.message("GitHub 公开贡献页面暂不可用。") }
        return days
    }

    private static func attributes(in tag: String) throws -> [String: String] {
        let pairs = try matches(#"([\w-]+)\s*=\s*[\"']([^\"']*)[\"']"#, in: tag)
        return pairs.reduce(into: [:]) { $0[$1[1]] = $1[2] }
    }

    private static func matches(_ pattern: String, in text: String) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}
