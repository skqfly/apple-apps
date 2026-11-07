import SwiftUI

struct BlogDetailScreen: View {
    let post: BlogPost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    if let category = post.category, !category.isEmpty {
                        Text(category).font(.subheadline.weight(.medium)).foregroundStyle(Color.appAccent)
                    }
                    Text(post.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    if post.date != .distantPast {
                        Text(post.date, format: .dateTime.year().month().day())
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !post.description.isEmpty {
                        Text(post.description).font(.title3).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }
                Divider()
                MarkdownBlocks(post.body, baseURL: post.websiteURL)
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
