import SwiftUI

struct AppNavigationView: View {
    @State private var selectedSection: SiteSection = .blog

    var body: some View {
        if #available(iOS 26, *) {
            liquidGlassTabs
        } else {
            legacyTabs
        }
    }

    @available(iOS 26, *)
    private var liquidGlassTabs: some View {
        TabView(selection: $selectedSection) {
            ForEach(SiteSection.allCases) { section in
                Tab(section.title, systemImage: section.symbolName, value: section) {
                    SectionScreen(section: section)
                }
            }
        }
        .tint(Color(red: 0.05, green: 0.38, blue: 0.95))
    }

    private var legacyTabs: some View {
        TabView(selection: $selectedSection) {
            ForEach(SiteSection.allCases) { section in
                SectionScreen(section: section)
                    .tabItem {
                        Image(systemName: section.symbolName)
                    }
                    .tag(section)
            }
        }
        .tint(Color(red: 0.05, green: 0.38, blue: 0.95))
    }
}

private struct SectionScreen: View {
    let section: SiteSection

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(section.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    PublicationStatusCard()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(SiteCanvasBackground())
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建", systemImage: "plus") {}
                        .accessibilityLabel("新建\(section.title)")
                }
            }
        }
    }
}

private struct PublicationStatusCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("发布队列", systemImage: "arrow.up.circle")
                .font(.headline)

            Text("内容连接还没有配置。导航先固定为网站现有的四个栏目，发布操作留在当前栏目内。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                StatusCount(title: "草稿", value: "0")
                StatusCount(title: "待发布", value: "0")
                StatusCount(title: "已发布", value: "0")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct StatusCount: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SiteCanvasBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.975, green: 0.967, blue: 0.953),
                Color(red: 0.945, green: 0.933, blue: 0.914)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
