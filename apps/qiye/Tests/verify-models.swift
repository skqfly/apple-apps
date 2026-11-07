import Foundation

// URL-only dependency used by BlogPost; production networking is exercised separately.
enum GitHubRepository { static let websiteURL = URL(string: "https://mmddskq.top")! }

private struct VerificationFailure: Error { let reason: String }
private func expect(_ condition: @autoclosure () -> Bool, _ reason: String) throws {
    if !condition() { throw VerificationFailure(reason: reason) }
}

@main struct VerifyModels {
    static func main() async throws {
        let html = """
        <td id="day-a" data-level="0" data-date="2026-01-01"></td>
        <td id="day-b" data-level="2" data-date="2026-01-02"></td>
        <td id="day-c" data-level="4" data-date="2026-01-03"></td>
        <tool-tip for="day-a">No contributions on January 1st.</tool-tip>
        <tool-tip for="day-b">1 contribution on January 2nd.</tool-tip>
        <tool-tip for="day-c">1,234 contributions on January 3rd.</tool-tip>
        """
        let days = try ContributionHTMLParser.parse(html)
        try expect(days.count == 3, "Dated contribution cells were lost")
        try expect(days.map(\.count) == [0, 1, 1234], "Contribution tooltip counts parsed incorrectly")
        let calendar = try DashboardContributions(days: days, source: .publicHTML)
        try expect(calendar.total == 1235, "Contribution total is incorrect")
        try expect(calendar.weeks.allSatisfy { $0.days.count == 7 }, "Calendar weeks need seven rows")
        let absent = try ContributionHTMLParser.parse("<td data-level='0' data-date='2026-01-01'></td>")
        let unknown = try DashboardContributions(days: absent, source: .publicHTML)
        try expect(unknown.total == nil, "Missing tooltips must not fabricate a zero count")
        do {
            _ = try DashboardContributions(days: [days[0], days[2]], source: .publicHTML)
            throw VerificationFailure(reason: "Calendar accepted a missing date")
        } catch is DashboardFailure { }
        do {
            _ = try DashboardContributions(days: [days[0], days[0]], source: .publicHTML)
            throw VerificationFailure(reason: "Calendar accepted duplicate dates")
        } catch is DashboardFailure { }
        let formatter = DashboardDates.dayFormatter()
        let leapNow = formatter.date(from: "2024-03-01")!
        let range = DashboardDates.range(now: leapNow)
        try expect(DashboardDates.calendar.dateComponents([.day], from: range.start, to: range.end).day == 365,
                   "Rolling-year range lost leap day")
        let running = DashboardWorkflowRun(id: 1, name: "Build", displayTitle: nil,
            status: "in_progress", conclusion: nil, headBranch: "main",
            htmlURL: URL(string: "https://github.com")!, updatedAt: .now, runNumber: 1)
        try expect(running.state.label == "运行中", "Pending workflow must not be marked successful")
        let markdown = """
        ---
        title: "文章 #1"
        pubDate: 2026-11-07
        description: >
          第一行摘要
          第二行摘要
        image: {"url":"/photos/example.jpg","alt":"封面"}
        ---
        # 正文
        保留 Markdown 正文。
        """
        let post = BlogPost.parse(markdown, path: "src/content/posts/example.md")
        try expect(post.title == "文章 #1", "Quoted frontmatter title changed")
        try expect(post.description == "第一行摘要 第二行摘要", "Folded YAML description changed")
        try expect(post.body.hasPrefix("# 正文"), "Frontmatter leaked into article body")
        try expect(post.imageURL?.absoluteString == "https://mmddskq.top/photos/example.jpg", "Relative article images resolved incorrectly")
        print("PASS: contribution parsing, missing counts, calendar gaps/duplicates/leap day, workflow state, article frontmatter and images")
    }
}
