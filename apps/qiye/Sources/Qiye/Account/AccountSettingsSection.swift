import SwiftUI

struct AccountSettingsSection: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("blogAuthor") private var blogAuthor = "skqfly"

    var body: some View {
        Section("偏好设置") {
            Picker("外观", selection: $appearance) {
                Text("跟随系统").tag("system")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
            }
            .accessibilityHint("更改栖页的显示外观")

            TextField("博客作者", text: $blogAuthor)
                .textContentType(.name)
                .accessibilityHint("保存在本机，作为博客作者的默认名称")
        }

        Section {
            if let url = URL(string: "https://mmddskq.top/projects") {
                Link(destination: url) {
                    Label("作品 · 在浏览器打开", systemImage: "arrow.up.right.square")
                }
            }
            if let url = URL(string: "https://mmddskq.top/friends") {
                Link(destination: url) {
                    Label("友链 · 在浏览器打开", systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text("网站入口")
        } footer: {
            Text("前往网站浏览作品和友链；栖页暂未提供这些内容的编辑功能。")
        }
    }
}
