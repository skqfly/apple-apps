import SwiftUI

struct BlogDetailScreen: View {
    let post: BlogPost
    @Environment(\.offlineWebsite) private var offlineWebsite

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(post.title).appContentTitle()
                    if let category = post.category, !category.isEmpty {
                        Text(category).font(.subheadline.weight(.medium)).foregroundStyle(Color.appAccent)
                    }
                    if post.date != .distantPast {
                        Text(post.date, format: .dateTime.year().month().day())
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !post.description.isEmpty {
                        Text(post.description).font(.body).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }
                if let url = post.imageURL {
                    if let local = offlineWebsite?.imageURL(for: url) {
                        Group {
                            if local.pathExtension.lowercased() == "svg" {
                                DirectorySVG(url: local) { Color.clear }
                            } else {
                                LocalPhotoImage(url: local, maximumPixelSize: 1_600)
                            }
                        }
                        .frame(height: 230).clipped().clipShape(.rect(cornerRadius: 20))
                    } else {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                                    .frame(height: 230).clipped().clipShape(.rect(cornerRadius: 20))
                            }
                        }
                    }
                }
                Divider()
                MarkdownBlocks(post.body, baseURL: post.websiteURL).lineSpacing(6)
            }
            .padding(.horizontal, AppPageLayout.horizontalInset)
            .padding(.top, AppPageLayout.topInset)
            .padding(.bottom, 22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .appPageBackground()
        .appNavigationTitle("博客")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: post.websiteURL) {
                    ToolbarActionIcon("分享", systemImage: "square.and.arrow.up")
                }

                Menu {
                    Link(destination: post.websiteURL) {
                        Label("在浏览器打开", systemImage: "safari")
                    }
                } label: {
                    ToolbarActionIcon("更多", systemImage: "ellipsis")
                }
            }
        }
    }
}
