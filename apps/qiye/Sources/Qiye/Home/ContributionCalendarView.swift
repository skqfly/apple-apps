import SwiftUI

struct ContributionCalendarView: View {
    let calendar: DashboardContributions
    var isLoading = false
    @State private var selectedDayID: String?
    @State private var visibleWeekID: String?
    @State private var showsDatePicker = false
    @ScaledMetric(relativeTo: .caption) private var scaledTileSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var monthLabelWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var monthHeaderHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var legendWidth: CGFloat = 18
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    private let gap: CGFloat = 4

    private var tileSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? max(44, scaledTileSize) : scaledTileSize
    }

    private var yearRange: String {
        let start = DashboardDates.calendar.component(.year, from: calendar.startDate)
        let end = DashboardDates.calendar.component(.year, from: calendar.endDate)
        return start == end ? "\(start.formatted(.number.grouping(.never)))" : "\(start.formatted(.number.grouping(.never)))–\(end.formatted(.number.grouping(.never)))"
    }

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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    heading
                    Spacer(minLength: 4)
                    rangeBadge
                }
                VStack(alignment: .leading, spacing: 10) {
                    heading
                    rangeBadge
                }
            }
            calendarGrid
                .environment(\.layoutDirection, .leftToRight)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    scrollHint
                    Spacer(minLength: 0)
                    intensityLegend
                }
                VStack(alignment: .leading, spacing: 8) {
                    scrollHint
                    intensityLegend
                }
            }

            DisclosureGroup(isExpanded: $showsDatePicker) {
                VStack(alignment: .leading, spacing: 10) {
                    if dynamicTypeSize.isAccessibilitySize {
                        DatePicker("查看日期", selection: selectedDate, in: calendar.startDate...calendar.endDate, displayedComponents: .date)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .accessibilityLabel("查看日期")
                            .environment(\.timeZone, DashboardDates.calendar.timeZone)
                            .environment(\.calendar, DashboardDates.calendar)
                    } else {
                        DatePicker("查看日期", selection: selectedDate, in: calendar.startDate...calendar.endDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .environment(\.timeZone, DashboardDates.calendar.timeZone)
                            .environment(\.calendar, DashboardDates.calendar)
                            .frame(minHeight: 44)
                    }
                    Text("\(calendar.startDate.formatted(Self.dateStyle)) — \(calendar.endDate.formatted(Self.dateStyle))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(calendar.source == .graphQL ? "来源：GitHub GraphQL" : "来源：GitHub 公开贡献")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("每日详情").font(.subheadline.weight(.medium))
                    Text(selectedDay.map(dayDescription) ?? "轻点方格，或按日期查找")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityHint("展开后可按日期查看每一天的真实贡献")

            HStack(alignment: .center, spacing: 8) {
                Link(destination: DashboardService.profileURL) {
                    Label("skqfly", systemImage: "arrow.up.right")
                        .font(.caption)
                        .frame(minHeight: 44)
                }
                Spacer(minLength: 0)
                Text("\(calendar.days.count) 天 · 每格一天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, -8)
            if calendar.total == nil {
                Text("部分日期未提供可靠次数，仅展示 GitHub 贡献等级。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = calendar.notice { DashboardErrorNote(message: notice) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [
                    DashboardStyle.surface(colorScheme),
                    colorScheme == .dark
                        ? Color(red: 0.045, green: 0.070, blue: 0.061)
                        : Color(red: 0.965, green: 0.990, blue: 0.979)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(LinearGradient(colors: [
                    DashboardStyle.outline(colorScheme),
                    DashboardStyle.outline(colorScheme).opacity(0.35),
                    DashboardStyle.outline(colorScheme).opacity(0.8)
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: accessibilityContrast == .increased ? 1.5 : 1)
        }
        .tint(DashboardStyle.accent(colorScheme))
        .onChange(of: calendar.endDate) {
            if selectedDay == nil { selectedDayID = nil }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("贡献").font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if isLoading {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在更新贡献")
                }
            }
            if let total = calendar.total {
                Text("\(total.formatted()) 次贡献")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("每日贡献活跃度")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rangeBadge: some View {
        Text(yearRange)
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(DashboardStyle.accent(colorScheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(DashboardStyle.accent(colorScheme).opacity(colorScheme == .dark ? 0.09 : 0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DashboardStyle.outline(colorScheme), lineWidth: 0.75)
            }
            .fixedSize()
            .accessibilityLabel("数据范围：\(calendar.startDate.formatted(Self.dateStyle)) 至 \(calendar.endDate.formatted(Self.dateStyle))")
    }

    private var scrollHint: some View {
        Label("横向查看 · 每列一周", systemImage: "arrow.left.and.right")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var intensityLegend: some View {
        HStack(spacing: 4) {
            Text("少")
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(tileColor(level))
                    .frame(width: 10, height: 10)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(tileOutline(level), lineWidth: 0.75)
                    }
            }
            Text("多")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("贡献等级图例，从少到多共五级")
    }

    private var calendarGrid: some View {
        GeometryReader { geometry in
            // Keep tiles readable and show only complete weeks, with equal outer margins.
            let availableWidth = max(tileSize, geometry.size.width - legendWidth - 8)
            let weekCount = min(calendar.weeks.count, max(1, Int((availableWidth + gap) / (tileSize + gap))))
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
                    .onChange(of: selectedDayID) {
                        guard let id = selectedDayID,
                              let index = calendar.weeks.firstIndex(where: { week in
                                  week.days.contains { $0?.id == id }
                              }) else { return }
                        let firstVisible = calendar.weeks.firstIndex { $0.id == visibleWeekID }
                            ?? max(0, calendar.weeks.count - weekCount)
                        if index < firstVisible || index >= firstVisible + weekCount {
                            let first = min(index, max(0, calendar.weeks.count - weekCount))
                            visibleWeekID = calendar.weeks[first].id
                        }
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
                    .font(.caption)
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
                    .font(.caption)
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
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [tileColor(day.level), tileColor(day.level).opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(LinearGradient(colors: [
                                        tileOutline(day.level),
                                        tileOutline(day.level).opacity(0.45)
                                    ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: accessibilityContrast == .increased ? 1.5 : 0.75)
                            }
                            .overlay {
                                if differentiateWithoutColor && day.level > 0 {
                                    Text("\(day.level)")
                                        .font(.system(size: max(9, tileSize * 0.62), weight: .semibold))
                                        .foregroundStyle(colorScheme == .dark
                                            ? (day.level <= 2 ? Color.white : Color.black)
                                            : (day.level >= 4 ? Color.white : Color.black))
                                }
                            }
                            .overlay {
                                if selectedDayID == day.id {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.primary, lineWidth: 2)
                                }
                            }
                            .frame(width: tileSize, height: tileSize)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dayDescription(day))
                    .accessibilityHint("显示这一天的贡献详情，也可展开每日详情按日期选择")
                    .accessibilityAddTraits(selectedDayID == day.id ? .isSelected : [])
                } else {
                    Color.clear.frame(width: tileSize, height: tileSize)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func tileColor(_ level: Int) -> Color {
        if colorScheme == .dark {
            switch level {
            case 0: return Color(red: 0.065, green: 0.115, blue: 0.090)
            case 1: return Color(red: 0.16, green: 0.34, blue: 0.25)
            case 2: return Color(red: 0.23, green: 0.49, blue: 0.35)
            case 3: return Color(red: 0.32, green: 0.66, blue: 0.47)
            default: return Color(red: 0.53, green: 0.86, blue: 0.67)
            }
        }
        switch level {
        case 0: return Color(red: 0.91, green: 0.95, blue: 0.93)
        case 1: return Color(red: 0.74, green: 0.88, blue: 0.81)
        case 2: return Color(red: 0.49, green: 0.74, blue: 0.62)
        case 3: return Color(red: 0.23, green: 0.55, blue: 0.42)
        default: return Color(red: 0.07, green: 0.35, blue: 0.26)
        }
    }

    private func tileOutline(_ level: Int) -> Color {
        if accessibilityContrast == .increased {
            return colorScheme == .dark
                ? Color(red: 0.60, green: 0.77, blue: 0.66)
                : Color(red: 0.24, green: 0.44, blue: 0.33)
        }
        if colorScheme == .dark {
            return level == 0
                ? Color(red: 0.27, green: 0.37, blue: 0.31)
                : Color(red: 0.65, green: 0.88, blue: 0.74).opacity(accessibilityContrast == .increased ? 1 : 0.7)
        }
        return level == 0
            ? Color(red: 0.62, green: 0.74, blue: 0.67)
            : Color(red: 0.15, green: 0.44, blue: 0.32).opacity(0.6)
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
