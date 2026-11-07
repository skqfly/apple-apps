import SwiftUI

struct WebsiteSettingsScreen: View {
    @AppStorage("blogAuthor") private var author = "skqfly"
    var body: some View {
        Form {
            Section("网站") {
                LabeledContent("站点", value: "mmddskq.top")
                LabeledContent("仓库", value: "skqfly.github.io")
                LabeledContent("发布分支", value: "main")
                Link("在浏览器打开网站", destination: URL(string: "https://mmddskq.top")!)
            }
            Section("博客") {
                TextField("默认作者", text: $author)
                Text("文章从 GitHub 读取，长文仍可在 Trilium 编辑和同步。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("低频栏目") {
                Link("作品项目", destination: URL(string: "https://mmddskq.top/projects")!)
                Link("朋友与友链", destination: URL(string: "https://mmddskq.top/friends")!)
            }
        }
        .navigationTitle("网站与博客")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PublishingSettingsScreen: View {
    var body: some View {
        Form {
            Section("内容来源") {
                LabeledContent("博客文章", value: "GitHub · Trilium 同步")
                LabeledContent("说说与照片", value: "GitHub · 栖页发布")
            }
            Section("发布记录") {
                Link("网站构建与部署", destination: URL(string: "https://github.com/skqfly/skqfly.github.io/actions")!)
                Link("查看提交历史", destination: URL(string: "https://github.com/skqfly/skqfly.github.io/commits/main")!)
            }
            Section {
                Text("每次发布会在网站仓库生成一个提交，随后由部署工作流构建网站。提交成功与网站部署成功分别显示。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("发布与同步")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppearanceSettingsScreen: View {
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Form {
            Picker("外观", selection: $appearance) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppInformationScreen: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("名称", value: "栖页 Qiye")
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
            Section {
                Link("应用源码", destination: URL(string: "https://github.com/skqfly/apple-apps")!)
            }
        }
        .navigationTitle("关于栖页")
        .navigationBarTitleDisplayMode(.inline)
    }
}
