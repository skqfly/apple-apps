import SwiftUI

// Cohesive palette aligned with the app's global design.
enum DashboardStyle {
    static func background(_ scheme: ColorScheme) -> Color {
        Color.appBackground
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        Color.appSurface
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        Color.appAccent
    }

    static func outline(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }
}

struct DashboardCard<Content: View>: View {
    let title: String
    let symbol: String
    let isLoading: Bool
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(title, systemImage: symbol == "github-mark" ? "chart.dots.scatter" : symbol)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在更新\(title)")
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 18)
    }
}

struct DashboardErrorNote: View {
    let message: String
    var showsPrevious = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(message, systemImage: "exclamationmark.circle")
            if showsPrevious { Text("正在显示上次成功获取的数据。") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct DashboardWorkflowRow: View {
    let run: DashboardWorkflowRun
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Link(destination: run.htmlURL) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: run.state.symbol)
                    .foregroundStyle(run.state.color)
                    .font(.title3)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { metadata }
                        VStack(alignment: .leading, spacing: 4) { metadata }
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("在 GitHub 打开工作流运行详情")
    }

    @ViewBuilder private var metadata: some View {
        Text(run.state.label).foregroundStyle(run.state.color)
        Text("#\(run.runNumber) · \(run.headBranch ?? "分支未知")")
            .foregroundStyle(.secondary)
        Text(run.updatedAt, style: .relative).foregroundStyle(.secondary)
    }
}

extension DashboardRunState {
    var color: Color {
        switch self {
        case .success: return .green
        case .failure, .timedOut: return .red
        case .running: return .appAccent
        case .queued, .waiting, .actionRequired: return .orange
        default: return .secondary
        }
    }
}
