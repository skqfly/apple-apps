import SwiftUI

enum CollectionStyle {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.84)
}

struct CollectionPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : CollectionStyle.spring, value: configuration.isPressed)
    }
}

struct CollectionHeading: View {
    let title: String
    var detail: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.tertiary) }
        }
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
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text).textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button("清除搜索", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(13)
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
    func collectionZoomDestination(id: String, namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { self }
    }

    func collectionSurface(radius: CGFloat = 22) -> some View {
        background(Color.appSurface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
            }
    }
}
