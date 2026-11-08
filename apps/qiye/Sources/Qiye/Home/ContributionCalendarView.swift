import SwiftUI

struct ContributionCalendarView: View {
    let calendar: DashboardContributions
    var isLoading = false
    @State private var selectedDayID: String?
    @State private var visibleWeekID: String?
    @State private var selectedYear: Int?
    @ScaledMetric(relativeTo: .caption) private var scaledTileSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var monthHeaderHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .caption) private var legendWidth: CGFloat = 32
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    private let gap: CGFloat = 4.5

    private var tileSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? max(40, scaledTileSize) : scaledTileSize
    }

    private var availableYears: [Int] {
        let years = calendar.days.map { DashboardDates.calendar.component(.year, from: $0.date) }
        let set = Array(Set(years)).sorted(by: >)
        return set.isEmpty ? [2026] : set
    }

    private var displayedYear: Int {
        selectedYear ?? DashboardDates.calendar.component(.year, from: calendar.endDate)
    }

    private var selectedDay: DashboardContributionDay? {
        calendar.days.first { $0.id == selectedDayID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            calendarGrid
                .environment(\.layoutDirection, .leftToRight)
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 24)
        .tint(Color.appAccent)
    }

    // MARK: - Header (matching the reference Activity card)

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Image("GitHubMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.primary)

                Text("Activity")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .accessibilityAddTraits(.isHeader)

                if isLoading {
                    ProgressView().controlSize(.small)
                        .padding(.leading, 4)
                        .accessibilityLabel("Updating activity")
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                // Interactive Year Menu
                Menu {
                    ForEach(availableYears, id: \.self) { year in
                        Button {
                            Haptics.selection()
                            scrollTo(year: year)
                        } label: {
                            HStack {
                                Text("\(year) 年")
                                if displayedYear == year {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button("回到最新") {
                        Haptics.medium()
                        selectedYear = nil
                        showRecentWeeks(12)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(displayedYear)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .liquidGlassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择年份，当前为 \(displayedYear) 年")

                // Menu button
                Link(destination: DashboardService.profileURL) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 30, height: 30)
                        .liquidGlassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View on GitHub")
            }
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        GeometryReader { geometry in
            let availableWidth = max(tileSize, geometry.size.width - legendWidth - 8)
            let weekCount = min(calendar.weeks.count, max(1, Int((availableWidth + gap) / (tileSize + gap))))
            let gridWidth = CGFloat(weekCount) * (tileSize + gap) - gap
            HStack(alignment: .top, spacing: 8) {
                weekdayLegend
                VStack(alignment: .leading, spacing: gap) {
                    monthHeader(weekCount: weekCount, width: gridWidth)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: gap) {
                            ForEach(calendar.weeks) { week in
                                weekColumn(week).id(week.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $visibleWeekID, anchor: .leading)
                    .frame(width: gridWidth, height: 7 * tileSize + 6 * gap)
                    .onChange(of: calendar.endDate, initial: true) {
                        showRecentWeeks(weekCount)
                    }
                    .onChange(of: weekCount) {
                        showRecentWeeks(weekCount)
                    }
                }
                .frame(width: gridWidth)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: monthHeaderHeight + 7 * tileSize + 7 * gap + 4)
    }

    private func showRecentWeeks(_ count: Int) {
        visibleWeekID = calendar.weeks.dropFirst(max(0, calendar.weeks.count - count)).first?.id
    }

    private func scrollTo(year: Int) {
        selectedYear = year
        if let targetWeek = calendar.weeks.first(where: { week in
            week.days.contains { day in
                guard let day else { return false }
                return DashboardDates.calendar.component(.year, from: day.date) == year
            }
        }) {
            withAnimation(.snappy(duration: 0.3)) {
                visibleWeekID = targetWeek.id
            }
        }
    }

    // English month abbreviations: Jan, Feb, Mar, etc.
    private static let englishMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private func monthHeader(weekCount: Int, width: CGFloat) -> some View {
        let firstIndex = calendar.weeks.firstIndex { $0.id == visibleWeekID }
            ?? max(0, calendar.weeks.count - weekCount)
        let weeks = Array(calendar.weeks.dropFirst(firstIndex).prefix(weekCount))
        let labelWidth: CGFloat = 32

        let labels = weeks.enumerated().compactMap { index, week -> (index: Int, text: String, x: CGFloat)? in
            let monthIndex: Int?
            if let firstDay = week.days.compactMap({ $0 }).first {
                let dayOfMonth = DashboardDates.calendar.component(.day, from: firstDay.date)
                if dayOfMonth <= 7 || index == 0 {
                    let m = DashboardDates.calendar.component(.month, from: firstDay.date)
                    monthIndex = m - 1
                } else {
                    monthIndex = nil
                }
            } else {
                monthIndex = nil
            }
            guard let m = monthIndex, m >= 0, m < Self.englishMonths.count else { return nil }
            let text = Self.englishMonths[m]
            return (index, text, min(CGFloat(index) * (tileSize + gap), max(0, width - labelWidth)))
        }

        let visibleLabels = labels.reversed().reduce(into: [(index: Int, text: String, x: CGFloat)]()) { result, label in
            if result.last.map({ $0.x - label.x >= labelWidth + gap }) ?? true {
                result.append(label)
            }
        }

        return ZStack(alignment: .topLeading) {
            ForEach(visibleLabels, id: \.index) { label in
                Text(label.text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, height: monthHeaderHeight, alignment: .leading)
                    .offset(x: label.x)
            }
        }
        .frame(width: width, height: monthHeaderHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    // English weekday abbreviations matching reference: Mon, Tue, Wed, Thu, Fri
    private var weekdayLegend: some View {
        VStack(spacing: gap) {
            Color.clear.frame(width: legendWidth, height: monthHeaderHeight)
            // 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
            ForEach(0..<7) { index in
                Text(weekdayTitle(for: index))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: legendWidth, height: tileSize, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    private func weekdayTitle(for index: Int) -> String {
        switch index {
        case 1: return "Mon"
        case 2: return "Tue"
        case 3: return "Wed"
        case 4: return "Thu"
        case 5: return "Fri"
        default: return ""
        }
    }

    private func weekColumn(_ week: DashboardContributionWeek) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<7) { index in
                if let day = week.days[index] {
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy(duration: 0.18)) {
                            selectedDayID = (selectedDayID == day.id ? nil : day.id)
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(tileFill(day.level))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(tileStroke(day.level), lineWidth: selectedDayID == day.id ? 1.8 : 0.6)
                            }
                            .shadow(color: day.level > 0 ? tileFill(day.level).opacity(0.35) : .clear, radius: 2, y: 1)
                            .frame(width: tileSize, height: tileSize)
                            .scaleEffect(selectedDayID == day.id ? 1.15 : 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dayAccessibility(day))
                } else {
                    Color.clear.frame(width: tileSize, height: tileSize)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: - Footer (refined and concise)

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            if let selectedDay {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tileFill(selectedDay.level))
                        .frame(width: 8, height: 8)
                    Text(dayDetailText(selectedDay))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if let total = calendar.total {
                Text("\(total.formatted()) contributions in the last year")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("Daily contribution levels")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Mini intensity legend (Green theme, not purple)
            HStack(spacing: 3.5) {
                Text("Less")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tileFill(level))
                        .frame(width: 8.5, height: 8.5)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .strokeBorder(tileStroke(level), lineWidth: 0.5)
                        }
                }
                Text("More")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Green Emerald Theme Colors (No Purple)

    private func tileFill(_ level: Int) -> Color {
        if colorScheme == .dark {
            switch level {
            case 0:
                return Color(white: 0.16).opacity(0.85)
            case 1:
                return Color(red: 0.18, green: 0.42, blue: 0.32)
            case 2:
                return Color(red: 0.25, green: 0.62, blue: 0.46)
            case 3:
                return Color(red: 0.35, green: 0.82, blue: 0.60)
            default:
                return Color(red: 0.48, green: 0.95, blue: 0.72)
            }
        } else {
            switch level {
            case 0:
                return Color(red: 0.90, green: 0.93, blue: 0.92)
            case 1:
                return Color(red: 0.65, green: 0.88, blue: 0.76)
            case 2:
                return Color(red: 0.40, green: 0.78, blue: 0.62)
            case 3:
                return Color(red: 0.20, green: 0.65, blue: 0.48)
            default:
                return Color(red: 0.08, green: 0.48, blue: 0.34)
            }
        }
    }

    private func tileStroke(_ level: Int) -> Color {
        if colorScheme == .dark {
            return level == 0
                ? Color.white.opacity(0.08)
                : Color.white.opacity(0.20)
        } else {
            return level == 0
                ? Color.black.opacity(0.06)
                : Color.black.opacity(0.12)
        }
    }

    private func dayDetailText(_ day: DashboardContributionDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        let dateStr = formatter.string(from: day.date)
        if let count = day.count {
            return "\(dateStr): \(count) contribution\(count == 1 ? "" : "s")"
        } else {
            return "\(dateStr): level \(day.level)"
        }
    }

    private func dayAccessibility(_ day: DashboardContributionDay) -> String {
        dayDetailText(day)
    }
}
