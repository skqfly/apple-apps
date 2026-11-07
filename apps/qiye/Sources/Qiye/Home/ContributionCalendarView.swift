import SwiftUI

struct ContributionCalendarView: View {
    let calendar: DashboardContributions
    @State private var selectedDayID: String?
    @State private var visibleWeekID: String?
    @ScaledMetric(relativeTo: .caption) private var tileSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var monthLabelWidth: CGFloat = 32
    @ScaledMetric(relativeTo: .caption2) private var monthHeaderHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var legendWidth: CGFloat = 22
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    private let gap: CGFloat = 4

    private var selectedDay: DashboardContributionDay? {
        calendar.days.first { $0.id == selectedDayID }
    }

    private var selectedDate: Binding<Date> {
        Binding(
            get: { selectedDay?.date ?? calendar.endDate },
            set: { selectedDayID = DashboardDates.dayFormatter().string(from: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                if let total = calendar.total {
                    Text(total, format: .number)
                        .font(.title2.bold().monospacedDigit())
                    Text("次贡献").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("每日贡献活跃度").font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 0)
            }
            Text("\(calendar.startDate.formatted(Self.dateStyle)) — \(calendar.endDate.formatted(Self.dateStyle))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            calendarGrid
                .environment(\.layoutDirection, .leftToRight)

            HStack(spacing: 5) {
                Image(systemName: "arrow.left.and.right")
                Text("横向查看全年")
                Spacer(minLength: 4)
                Text("少")
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tileColor(level))
                        .frame(width: 10, height: 10)
                        .overlay {
                            if differentiateWithoutColor && level > 0 {
                                Text("\(level)").font(.system(size: 7)).foregroundStyle(.primary)
                            }
                        }
                        .accessibilityHidden(true)
                }
                Text("多")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("贡献等级图例，从少到多共五级。日历可横向滚动。")

            DatePicker("查看日期", selection: selectedDate, in: calendar.startDate...calendar.endDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(.caption)
                .environment(\.timeZone, DashboardDates.calendar.timeZone)

            if let day = selectedDay {
                Text(dayDescription(day))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.updatesFrequently)
            } else {
                Text("轻点方格查看当天贡献")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(calendar.source == .graphQL ? "来源：GitHub GraphQL · skqfly" : "来源：GitHub 公开贡献 · skqfly")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if calendar.total == nil {
                Text("部分日期未提供可靠次数，仅展示 GitHub 贡献等级。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notice = calendar.notice {
                DashboardErrorNote(message: notice)
            }
        }
    }

    private var calendarGrid: some View {
        GeometryReader { geometry in
            // Keep tiles readable and show only complete weeks, with equal outer margins.
            let availableWidth = max(tileSize, geometry.size.width - legendWidth - 8)
            let weekCount = min(calendar.weeks.count, min(15, max(1, Int((availableWidth + gap) / (tileSize + gap)))))
            let gridWidth = CGFloat(weekCount) * (tileSize + gap) - gap
            HStack(alignment: .top, spacing: 8) {
                weekdayLegend
                VStack(alignment: .leading, spacing: gap) {
                    monthHeader(weekCount: weekCount, width: gridWidth)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: gap) {
                            ForEach(calendar.weeks) { week in
                                weekColumn(week).id(week.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
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
            .padding(.top, 2)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: monthHeaderHeight + 7 * tileSize + 7 * gap + 8)
    }

    private func showRecentWeeks(_ count: Int) {
        visibleWeekID = calendar.weeks.dropFirst(max(0, calendar.weeks.count - count)).first?.id
    }

    private func monthHeader(weekCount: Int, width: CGFloat) -> some View {
        let firstIndex = calendar.weeks.firstIndex { $0.id == visibleWeekID }
            ?? max(0, calendar.weeks.count - weekCount)
        let weeks = Array(calendar.weeks.dropFirst(firstIndex).prefix(weekCount))
        // Clamp labels inside the viewport. Give the newest month priority if labels overlap.
        let labels = weeks.enumerated().compactMap { index, week -> (index: Int, text: String, x: CGFloat)? in
            let text = week.monthLabel ?? (index == 0 ? week.days.compactMap { $0 }.first.map {
                "\(DashboardDates.calendar.component(.month, from: $0.date))月"
            } : nil)
            guard let text else { return nil }
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
                    .fixedSize()
                    .frame(width: monthLabelWidth, height: monthHeaderHeight, alignment: .leading)
                    .offset(x: label.x)
            }
        }
        .frame(width: width, height: monthHeaderHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var weekdayLegend: some View {
        VStack(spacing: gap) {
            Color.clear.frame(width: legendWidth, height: monthHeaderHeight)
            ForEach(0..<7) { index in
                Text([1: "一", 3: "三", 5: "五"][index] ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: legendWidth, height: tileSize)
            }
        }
        .accessibilityHidden(true)
    }

    private func weekColumn(_ week: DashboardContributionWeek) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<7) { index in
                if let day = week.days[index] {
                    Button { selectedDayID = day.id } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tileColor(day.level))
                            .overlay {
                                if differentiateWithoutColor && day.level > 0 {
                                    Text("\(day.level)")
                                        .font(.system(size: max(8, tileSize * 0.65), weight: .medium))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .overlay {
                                if selectedDayID == day.id {
                                    RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(Color.primary, lineWidth: 1.5)
                                }
                            }
                            .frame(width: tileSize, height: tileSize)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dayDescription(day))
                    .accessibilityHint("显示这一天的贡献详情")
                    .accessibilityAddTraits(selectedDayID == day.id ? .isSelected : [])
                } else {
                    Color.clear.frame(width: tileSize, height: tileSize)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func tileColor(_ level: Int) -> Color {
        switch level {
        case 0: return Color.contributionInk.opacity(0.10)
        case 1: return Color.contributionInk.opacity(0.28)
        case 2: return Color.contributionInk.opacity(0.48)
        case 3: return Color.contributionInk.opacity(0.72)
        default: return Color.contributionInk
        }
    }

    private static var dateStyle: Date.FormatStyle {
        Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: DashboardDates.calendar.timeZone)
    }

    private func dayDescription(_ day: DashboardContributionDay) -> String {
        let date = day.date.formatted(Self.dateStyle.weekday())
        if let count = day.count { return "\(date)，\(count) 次贡献" }
        return "\(date)，贡献等级 \(day.level)/4，次数未提供"
    }
}
