import SwiftUI

/// A GitHub-style scrollable filter bar: pill buttons with the selected item
/// rendered dark and inverted, unselected items on a light secondary fill.
/// Fully adopts Liquid Glass on iOS 26+ and refined translucent capsules on fallback.
struct ContentStatusPicker: View {
    @Binding var selection: ContentStatusFilter
    let counts: [ContentStatusFilter: Int]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 8) {
                    pillsRow
                }
            } else {
                pillsRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("content-status-picker")
    }

    private var pillsRow: some View {
        HStack(spacing: 8) {
            ForEach(ContentStatusFilter.allCases) { status in
                pill(for: status)
            }
        }
        .padding(.vertical, 2)
    }

    private func pill(for status: ContentStatusFilter) -> some View {
        let isSelected = selection == status
        let count = counts[status, default: 0]
        return Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.22)) {
                selection = status
            }
        } label: {
            HStack(spacing: 6) {
                Text(status.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(
                            isSelected ? Color.white.opacity(0.20) : Color.secondary.opacity(0.12)
                        )
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .modifier(PillGlassBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.title)，\(count) 项")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("content-status-\(status.rawValue)")
    }
}

private struct PillGlassBackground: ViewModifier {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if isSelected {
                content
                    .glassEffect(.regular.tint(Color.appAccent).interactive(), in: .capsule)
            } else {
                content
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            content
                .background(
                    Capsule().fill(
                        isSelected
                            ? (colorScheme == .dark ? Color.white.opacity(0.20) : Color.primary.opacity(0.86))
                            : Color.secondary.opacity(0.10)
                    )
                )
                .overlay {
                    if !isSelected {
                        Capsule().strokeBorder(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05), lineWidth: 0.5)
                    }
                }
        }
    }
}
