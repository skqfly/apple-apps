import SwiftUI

struct BlogDetailScreen: View {
    let post: BlogPost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let url = post.imageURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .frame(height: 230).clipped().clipShape(.rect(cornerRadius: 20))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    if let category = post.category, !category.isEmpty {
                        Text(category).font(.subheadline.weight(.medium)).foregroundStyle(Color.appAccent)
                    }
                    Text(post.title).font(.system(.largeTitle, design: .serif).weight(.semibold)).accessibilityAddTraits(.isHeader)
                    if post.date != .distantPast {
                        Text(post.date, format: .dateTime.year().month().day())
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !post.description.isEmpty {
                        Text(post.description).font(.title3).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }
                Divider()
                MarkdownBlocks(post.body, baseURL: post.websiteURL).lineSpacing(6)
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle("文章")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: post.websiteURL) {
                    Label("分享文章", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
