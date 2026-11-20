import SwiftUI

struct ContributionCalendarView: View {
    let calendar: DashboardContributions
    var isLoading = false
    @State private var selectedDayID: String?
    @State private var visibleWeekID: String?
    @State private var selectedYear: Int?
    @ScaledMetric(relativeTo: .caption) private var scaledTileSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var monthLabelHeight: CGFloat = 16
    @ScaledMetric(relativeTo: .caption2) private var monthLabelWidth: CGFloat = 32
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let gap: CGFloat = 3

    private var tileSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? max(44, scaledTileSize) : scaledTileSize
    }

    private var availableYears: [Int] {
        let years = calendar.days.map { DashboardDates.calendar.component(.year, from: $0.date) }
        let set = Array(Set(years)).sorted(by: >)
        return set.isEmpty ? [2026] : set
    }

    private var displayedYear: Int {
        selectedYear ?? DashboardDates.calendar.component(.year, from: calendar.endDate)
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                header
                summary
                calendarGrid.environment(\.layoutDirection, .leftToRight)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .collectionSurface(radius: 16)

            recentActivity
        }
    }

    private var summary: some View {
        let totals = calendar.weekTotals
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("当前连续")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(calendar.currentStreak) 天")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                if let total = calendar.total {
                    Text("过去一年贡献 \(total.formatted()) 次")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text("本周贡献")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let current = totals.current {
                    Text(current.formatted())
                        .font(.title2.bold())
                        .monospacedDigit()
                    if let previous = totals.previous {
                        let difference = current - previous
                        Text("较上周同期 \(difference > 0 ? "+" : "")\(difference.formatted())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("暂无次数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var recentActivity: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 4))

        return VStack(alignment: .leading, spacing: 8) {
            Text("最近 7 天")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            layout {
                ForEach(calendar.days.suffix(7)) { day in
                    let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
                    let dayLayout = isAccessibilitySize
                        ? AnyLayout(HStackLayout(spacing: 8))
                        : AnyLayout(VStackLayout(spacing: 4))

                    dayLayout {
                        Text(day.count.map { $0.formatted() } ?? "—")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(day.hasActivity ? Color.appSurface : Color.primary)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 30, minHeight: 30)
                            .background(day.hasActivity ? Color.primary : tileFill(0), in: Capsule())
                        Text(Self.weekdayFormatter.string(from: day.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: isAccessibilitySize ? .leading : .center)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dayAccessibility(day))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .collectionSurface(radius: 16)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Text("贡献活动")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .accessibilityAddTraits(.isHeader)

                if isLoading {
                    ProgressView().controlSize(.small)
                        .padding(.leading, 4)
                        .accessibilityLabel("正在更新贡献活动")
                }
            }

            Spacer(minLength: 8)

            Menu {
                Picker("年份", selection: Binding(
                    get: { displayedYear },
                    set: { year in
                        Haptics.selection()
                        scrollTo(year: year)
                    }
                )) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(verbatim: "\(year) 年").tag(year)
                    }
                }
                .pickerStyle(.inline)

                Button("回到最新", systemImage: "arrow.clockwise") {
                    Haptics.medium()
                    selectedYear = nil
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                        visibleWeekID = calendar.weeks.last?.id
                    }
                }

                Link(destination: DashboardService.profileURL) {
                    Label("在 GitHub 中查看", systemImage: "arrow.up.right")
                }
            } label: {
                HStack(spacing: 5) {
                    Text(verbatim: "\(displayedYear)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .accessibilityLabel("选择年份，当前为 \(displayedYear) 年")
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        GeometryReader { geometry in
            let availableWidth = max(tileSize, geometry.size.width)
            let weekCount = min(calendar.weeks.count, max(1, Int((availableWidth + gap) / (tileSize + gap))))
            let gridWidth = CGFloat(weekCount) * (tileSize + gap) - gap

            VStack(alignment: .leading, spacing: gap) {
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
                    selectedDayID = nil
                    showRecentWeeks(weekCount)
                }
                .onChange(of: weekCount) {
                    showRecentWeeks(weekCount)
                }
                monthHeader(weekCount: weekCount, width: gridWidth)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: monthLabelHeight + 7 * tileSize + 7 * gap)
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
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                visibleWeekID = targetWeek.id
            }
        }
    }

    private func monthHeader(weekCount: Int, width: CGFloat) -> some View {
        let firstIndex = calendar.weeks.firstIndex { $0.id == visibleWeekID }
            ?? max(0, calendar.weeks.count - weekCount)
        let weeks = Array(calendar.weeks.dropFirst(firstIndex).prefix(weekCount))

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
            guard let monthIndex else { return nil }
            let text = "\(monthIndex + 1)月"
            return (index, text, min(CGFloat(index) * (tileSize + gap), max(0, width - monthLabelWidth)))
        }

        let visibleLabels = labels.reversed().reduce(into: [(index: Int, text: String, x: CGFloat)]()) { result, label in
            if result.last.map({ $0.x - label.x >= monthLabelWidth + gap }) ?? true {
                result.append(label)
            }
        }

        return ZStack(alignment: .topLeading) {
            ForEach(visibleLabels, id: \.index) { label in
                Text(label.text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: monthLabelWidth, height: monthLabelHeight, alignment: .leading)
                    .offset(x: label.x)
            }
        }
        .frame(width: width, height: monthLabelHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func weekColumn(_ week: DashboardContributionWeek) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<7) { index in
                if let day = week.days[index] {
                    Button {
                        Haptics.selection()
                        selectedDayID = day.id
                    } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tileFill(day.level))
                            .overlay {
                                if selectedDayID == day.id {
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Color.primary, lineWidth: 1.5)
                                }
                            }
                            .frame(width: tileSize, height: tileSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dayAccessibility(day))
                    .popover(isPresented: Binding(
                        get: { selectedDayID == day.id },
                        set: { if !$0 && selectedDayID == day.id { selectedDayID = nil } }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Self.dateFormatter.string(from: day.date))
                                .font(.headline)
                            Text(dayCountText(day))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .presentationCompactAdaptation(.popover)
                    }
                } else {
                    Color.clear.frame(width: tileSize, height: tileSize)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func tileFill(_ level: Int) -> Color {
        let intensity = [0.08, 0.25, 0.44, 0.68, 0.92]
        return Color.primary.opacity(intensity[min(max(level, 0), intensity.count - 1)])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DashboardDates.dayFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日，EEEE"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DashboardDates.dayFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private func dayCountText(_ day: DashboardContributionDay) -> String {
        if let count = day.count { return "\(count.formatted()) 次贡献" }
        return "贡献强度 \(day.level) 级，次数未提供"
    }

    private func dayAccessibility(_ day: DashboardContributionDay) -> String {
        "\(Self.dateFormatter.string(from: day.date))，\(dayCountText(day))"
    }
}
