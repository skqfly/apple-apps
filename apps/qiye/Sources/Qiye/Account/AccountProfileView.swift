import SwiftUI

struct AccountProfileView: View {
    let name: String
    let avatarURL: URL?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title) private var avatarSize = 56

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            avatar
            identity
            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        ZStack {
            if let avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.appAccent.opacity(0.8))
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.appAccent.opacity(0.8))
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.appAccent.opacity(0.25), lineWidth: 1.5)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 6, y: 2)
        .accessibilityHidden(true)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name.isEmpty ? "skqfly" : name)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("@skqfly")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
