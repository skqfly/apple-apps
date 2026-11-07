import SwiftUI

struct WritingScreen: View {
    let section: SiteSection
    let overview: SiteOverview

    var body: some View {
        Group {
            if section == .talks {
                List(overview.talks) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(entry.date)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(entry.title).font(.headline)
                        Text(entry.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Link("在网站查看", destination: URL(string: "https://mmddskq.top/talks")!)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 8)
                }
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView {
                    Label("博客", systemImage: "doc.text")
                } description: {
                    Text("文章编辑将在下一步接入，这里先保留博客入口。")
                } actions: {
                    Link("查看网站文章", destination: URL(string: "https://mmddskq.top/blog")!)
                        .buttonStyle(.bordered)
                }
            }
        }
        .background(Color.appBackground)
        .navigationTitle(section.title)
    }
}
