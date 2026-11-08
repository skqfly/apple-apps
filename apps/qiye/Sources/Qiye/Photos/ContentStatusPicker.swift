import SwiftUI

/// A GitHub-style scrollable filter bar: pill buttons with the selected item
/// rendered dark and inverted, unselected items on a light secondary fill.
struct ContentStatusPicker: View {
    @Binding var selection: ContentStatusFilter
    let counts: [ContentStatusFilter: Int]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ContentStatusFilter.allCases) { status in
                    pill(for: status)
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("content-status-picker")
    }

    private func pill(for status: ContentStatusFilter) -> some View {
        let isSelected = selection == status
        let count = counts[status, default: 0]
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = status }
        } label: {
            HStack(spacing: 5) {
                Text(status.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.72) : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(
                            isSelected ? Color.white.opacity(0.16) : Color.secondary.opacity(0.12)
                        )
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                Capsule().fill(
                    isSelected
                        ? (colorScheme == .dark ? Color.white.opacity(0.16) : Color.primary.opacity(0.86))
                        : Color.secondary.opacity(0.10)
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.title)，\(count) 项")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("content-status-\(status.rawValue)")
    }
}
