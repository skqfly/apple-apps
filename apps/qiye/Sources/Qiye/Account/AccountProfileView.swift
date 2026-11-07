import SwiftUI

struct AccountProfileView: View {
    let name: String
    let avatarURL: URL?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var avatarSize = 56

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

        layout {
            avatar
            identity
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        AsyncImage(url: avatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("@skqfly")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("GitHub 身份已验证", systemImage: "checkmark.shield")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
