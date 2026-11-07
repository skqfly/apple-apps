import SwiftUI

struct ContributionCalendarView: View {
    let calendar: DashboardContributions
    @State private var selectedDayID: String?
    @ScaledMetric(relativeTo: .caption) private var tileSize: CGFloat = 12
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    private let gap: CGFloat = 4

    private var selectedDay: DashboardContributionDay? {
        calendar.days.first { $0.id == selectedDayID }
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
            HStack(alignment: .top, spacing: 8) {
                weekdayLegend
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(calendar.weeks) { week in
                                weekColumn(week).id(week.id)
                            }
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                    }
                    .defaultScrollAnchor(.trailing)
                    .onChange(of: calendar.endDate) {
                        if let id = calendar.weeks.last?.id { proxy.scrollTo(id, anchor: .trailing) }
                    }
                }
            }
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

    private var weekdayLegend: some View {
        VStack(spacing: gap) {
            Color.clear.frame(width: 22, height: 20)
            ForEach(0..<7) { index in
                Text([1: "一", 3: "三", 5: "五"][index] ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: tileSize)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private func weekColumn(_ week: DashboardContributionWeek) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            Text(week.monthLabel ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
                .frame(width: tileSize, height: 20, alignment: .leading)
                .accessibilityHidden(true)
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
        case 0: return Color.primary.opacity(0.07)
        case 1: return Color.appAccent.opacity(0.27)
        case 2: return Color.appAccent.opacity(0.48)
        case 3: return Color.appAccent.opacity(0.72)
        default: return Color.appAccent
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
