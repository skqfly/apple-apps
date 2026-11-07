import SwiftUI

struct HomeScreen: View {
    let overview: SiteOverview
    let photoCount: Int
    let draftCount: Int
    let openPhotos: () -> Void
    let openTalks: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                introduction
                photoFeature
                quickActions
                recentTalk
                if let error = overview.error {
                    Label(error, systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .navigationTitle("首页")
        .refreshable { await overview.refresh() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("栖页")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("给日常一个落点。")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Text("写下想法，留住眼前。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var photoFeature: some View {
        Button(action: openPhotos) {
            VStack(alignment: .leading, spacing: 0) {
                Image("HomeCover")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 218)
                    .clipped()
                    .accessibilityHidden(true)
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("照片里的生活")
                            .font(.headline)
                        Text("\(photoCount) 张已收录 · \(draftCount) 张本机待整理")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.title3)
                        .accessibilityHidden(true)
                }
                .padding(18)
            }
            .foregroundStyle(.primary)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24))
            .clipShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开照片，\(photoCount) 张已收录，\(draftCount) 张本机待整理")
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button(action: openPhotos) {
                Label("添加照片", systemImage: "photo.badge.plus")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            Button(action: openTalks) {
                Label("看看说说", systemImage: "text.bubble")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))
        }
    }

    @ViewBuilder
    private var recentTalk: some View {
        if let talk = overview.talks.first {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("最近说说").font(.headline)
                    Spacer()
                    Button("全部", action: openTalks)
                        .font(.subheadline)
                }
                Button {
                    openURL(URL(string: "https://mmddskq.top/talks")!)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(talk.date)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(talk.title)
                            .font(.title3.weight(.medium))
                        Text(talk.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20))
                }
                .foregroundStyle(.primary)
                .buttonStyle(.plain)
            }
        }
    }
}
