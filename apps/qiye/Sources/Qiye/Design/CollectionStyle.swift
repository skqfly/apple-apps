import SwiftUI

enum CollectionStyle {
    static let spring = Animation.snappy(duration: 0.22)
}

struct CollectionPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35)
            .animation(reduceMotion ? nil : CollectionStyle.spring, value: configuration.isPressed)
    }
}

struct CollectionFilterBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
        }
    }
}

struct CollectionFilterChip: View {
    let title: String
    let isSelected: Bool
    let select: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : CollectionStyle.spring) { select() }
            Haptics.selection()
        } label: {
            Text(title)
        }
        .contentActionStyle(isSelected ? .prominent : .standard)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Uses the existing bundled photograph previews, including when offline.
struct CollectionArtwork: View {
    let name: String

    var body: some View {
        GeometryReader { geometry in
            if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "PhotoPreviews")
                ?? Bundle.main.url(forResource: name, withExtension: "jpg") {
                LocalPhotoImage(url: url)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                Image("HomeCover").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }
        .accessibilityHidden(true)
    }
}

struct CollectionSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text).textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Label("清除搜索", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: ButtonMetrics.minimumHitSide, minHeight: ButtonMetrics.minimumHitSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CollectionPressStyle())
            }
        }
        .font(.subheadline)
        .frame(minHeight: ButtonMetrics.minimumHitSide)
        .padding(.leading, 14)
        .padding(.trailing, text.isEmpty ? 14 : 0)
        .background(Color.appSurface, in: .rect(cornerRadius: 16))
    }
}

extension View {
    @ViewBuilder
    func collectionZoomSource(id: String, namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else { self }
    }

    @ViewBuilder
    func collectionZoomDestination(id: String, namespace: Namespace.ID, enabled: Bool = true) -> some View {
        if #available(iOS 18, *), enabled {
            environment(\.usesCollectionZoom, true)
                .navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { self }
    }

    func collectionSurface(radius: CGFloat = 22) -> some View {
        background(Color.appSurface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension EnvironmentValues {
    @Entry var usesCollectionZoom = false
}

enum AppPageLayout {
    static let horizontalInset: CGFloat = 16
    static let topInset: CGFloat = 12
}

extension View {
    func appNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }

    func appContentTitle() -> some View {
        font(.title2.weight(.semibold))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
