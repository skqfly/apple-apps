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
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.06)
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))

        return Link(destination: run.htmlURL) {
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { metadata }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 3) { metadata }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Label {
                    Text(run.state.label)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: run.state.symbol)
                        .foregroundStyle(run.state.color)
                }
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("在 GitHub 打开工作流运行详情")
    }

    @ViewBuilder private var metadata: some View {
        Text("#\(run.runNumber) · \(run.headBranch ?? "分支未知")")
        Text(run.updatedAt, style: .relative)
    }
}

extension DashboardRunState {
    var color: Color {
        switch self {
        case .success: return Color(red: 0.16, green: 0.65, blue: 0.45)
        case .failure, .timedOut: return Color(red: 0.88, green: 0.28, blue: 0.28)
        case .running: return Color.appAccent
        case .queued, .waiting, .actionRequired: return Color.orange
        default: return .secondary
        }
    }
}
