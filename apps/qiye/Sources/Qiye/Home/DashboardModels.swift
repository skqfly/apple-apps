import Foundation

struct DashboardResource<Value: Sendable>: Sendable {
    var value: Value?
    var error: String?
    var isLoading = false
    var updatedAt: Date?
}

struct WebsiteHealth: Sendable {
    let statusCode: Int
    let duration: TimeInterval
    let checkedAt: Date
    var isReachable: Bool { (200..<400).contains(statusCode) }
}

struct DashboardRepository: Decodable, Sendable {
    let fullName: String
    let htmlURL: URL
    let defaultBranch: String
    let updatedAt: Date
    let pushedAt: Date?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name", htmlURL = "html_url"
        case defaultBranch = "default_branch", updatedAt = "updated_at", pushedAt = "pushed_at"
    }
}

struct DashboardWorkflowRun: Decodable, Identifiable, Sendable {
    let id: Int64
    let name: String?
    let displayTitle: String?
    let status: String
    let conclusion: String?
    let headBranch: String?
    let htmlURL: URL
    let updatedAt: Date
    let runNumber: Int

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case displayTitle = "display_title", headBranch = "head_branch", htmlURL = "html_url"
        case updatedAt = "updated_at", runNumber = "run_number"
    }

    var title: String { name ?? displayTitle ?? "工作流 #\(runNumber)" }
    var state: DashboardRunState {
        if status != "completed" {
            switch status {
            case "in_progress": return .running
            case "queued", "requested", "pending": return .queued
            case "waiting": return .waiting
            default: return .unknown
            }
        }
        switch conclusion {
        case "success": return .success
        case "failure", "startup_failure": return .failure
        case "timed_out": return .timedOut
        case "cancelled": return .cancelled
        case "skipped": return .skipped
        case "neutral": return .neutral
        case "action_required": return .actionRequired
        case "stale": return .stale
        default: return .unknown
        }
    }
}

enum DashboardRunState: Sendable {
    case success, failure, running, queued, waiting, timedOut, cancelled
    case skipped, neutral, actionRequired, stale, unknown

    var label: String {
        switch self {
        case .success: return "成功"
        case .failure: return "失败"
        case .running: return "运行中"
        case .queued: return "排队中"
        case .waiting: return "等待中"
        case .timedOut: return "超时"
        case .cancelled: return "已取消"
        case .skipped: return "已跳过"
        case .neutral: return "中立"
        case .actionRequired: return "需操作"
        case .stale: return "已过期"
        case .unknown: return "未知状态"
        }
    }

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure, .timedOut: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .queued, .waiting: return "clock"
        case .cancelled, .stale: return "minus.circle"
        case .skipped: return "arrow.right.circle"
        case .actionRequired: return "exclamationmark.circle.fill"
        case .neutral: return "circle.lefthalf.filled"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct DashboardPages: Decodable, Sendable {
    struct Source: Decodable, Sendable { let branch: String? }
    let status: String?
    let htmlURL: URL?
    let source: Source?

    enum CodingKeys: String, CodingKey {
        case status, source
        case htmlURL = "html_url"
    }

    var statusLabel: String {
        switch status {
        case "built": return "已构建"
        case "building": return "构建中"
        case "errored": return "构建失败"
        default: return "未返回构建状态"
        }
    }
}

struct DashboardContributionDay: Identifiable, Sendable {
    let id: String
    let date: Date
    let level: Int
    let count: Int?
}

struct DashboardContributionWeek: Identifiable, Sendable {
    let id: String
    // Sunday through Saturday. Padding cells have no contribution data.
    let days: [DashboardContributionDay?]
    let monthLabel: String?
}

struct DashboardContributions: Sendable {
    enum Source: Sendable { case graphQL, publicHTML }
    let days: [DashboardContributionDay]
    let weeks: [DashboardContributionWeek]
    let startDate: Date
    let endDate: Date
    let total: Int?
    let source: Source
    let notice: String?

    init(days: [DashboardContributionDay], source: Source, notice: String? = nil) throws {
        let sorted = days.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else {
            throw DashboardFailure.message("GitHub 未返回贡献日历。")
        }
        let calendar = DashboardDates.calendar
        let expected = calendar.dateComponents([.day], from: first.date, to: last.date).day.map { $0 + 1 }
        guard expected == sorted.count, Set(sorted.map(\.id)).count == sorted.count else {
            throw DashboardFailure.message("GitHub 贡献日历不完整，请重试。")
        }
        self.days = sorted
        startDate = first.date
        endDate = last.date
        self.source = source
        self.notice = notice
        total = sorted.allSatisfy { $0.count != nil } ? sorted.reduce(0) { $0 + ($1.count ?? 0) } : nil

        let firstWeekday = calendar.component(.weekday, from: first.date) - 1
        var cells = Array<DashboardContributionDay?>(repeating: nil, count: firstWeekday)
        cells.append(contentsOf: sorted.map(Optional.some))
        while cells.count % 7 != 0 { cells.append(nil) }
        var result: [DashboardContributionWeek] = []
        for offset in stride(from: 0, to: cells.count, by: 7) {
            let week = Array(cells[offset..<(offset + 7)])
            let valid = week.compactMap { $0 }
            guard let leading = valid.first else { continue }
            let monthStart = valid.first { calendar.component(.day, from: $0.date) == 1 }
            let labelDate = monthStart?.date ?? (offset == 0 && calendar.component(.day, from: leading.date) < 25 ? leading.date : nil)
            let label = labelDate.map { "\(calendar.component(.month, from: $0))月" }
            result.append(.init(id: leading.id, days: week, monthLabel: label))
        }
        weeks = result
    }
}

enum DashboardDates {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 1
        return calendar
    }

    static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    static func range(now: Date = .now) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: now)
        let previousYear = calendar.date(byAdding: .year, value: -1, to: end) ?? end
        let start = calendar.date(byAdding: .day, value: 1, to: previousYear) ?? previousYear
        return (start, end)
    }
}

enum DashboardFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
