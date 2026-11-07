import SwiftUI

struct ProfileAvatar: View {
    let isSignedIn: Bool
    let avatarURL: URL?
    @ScaledMetric(relativeTo: .body) private var size = 32

    var body: some View {
        Group {
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
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
        }
        .padding(4)
        .background(Color.appSurface, in: Circle())
        .clipShape(Circle())
        .contentShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.appAccent)
    }
}
