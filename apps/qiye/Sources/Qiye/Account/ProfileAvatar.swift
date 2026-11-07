import SwiftUI

struct ProfileAvatar: View {
    let isSignedIn: Bool
    let avatarURL: URL?
    private let size: CGFloat = 38

    var body: some View {
        avatar
            .frame(width: size, height: size)
            .clipShape(Circle())
            .padding(3)
            .modifier(ProfileGlassRing())
            .contentShape(Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatar: some View {
        if isSignedIn, let avatarURL {
            AsyncImage(url: avatarURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.appAccent)
            .padding(1)
            .background(Color.appSurface, in: Circle())
    }
}

/// A pressable ring. iOS 26 uses interactive Liquid Glass; earlier systems use a translucent ring.
struct ProfileGlassRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6) }
        }
    }
}
