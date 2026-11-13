import SwiftUI

struct ContentStatusPicker: View {
    @Binding var selection: ContentStatusFilter
    var categories: [ContentStatusFilter] = [.published, .unpublished]
    let counts: [ContentStatusFilter: Int]
    var titleOverrides: [ContentStatusFilter: String] = [:]
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(categories) { status in
                let selected = selection == status
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : CollectionStyle.spring) { selection = status }
                } label: {
                    HStack(spacing: 6) {
                        Text(titleOverrides[status] ?? status.title).font(.caption.weight(.semibold))
                        Text("\(counts[status, default: 0])").font(.caption2.monospacedDigit()).opacity(0.65)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .foregroundStyle(selected ? Color.appBackground : Color.secondary)
                    .background {
                        if selected {
                            Capsule().fill(Color.primary).matchedGeometryEffect(id: "status", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(CollectionPressStyle())
                .accessibilityLabel("\(titleOverrides[status] ?? status.title)，\(counts[status, default: 0]) 项")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("content-status-\(status.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("content-status-picker")
    }
}
