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
    @AppStorage("appearance") private var appearance = "dark"
    @State private var theme = AppTheme.shared
    @State private var customColor: Color = AppTheme.shared.accentColor

    var body: some View {
        Form {
            Section("模式") {
                Picker("外观模式", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.inline)
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("预设颜色")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                        ForEach(AppTheme.presets) { preset in
                            Button {
                                theme.selectPreset(preset)
                                customColor = preset.color
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 44, height: 44)
                                            .shadow(color: preset.color.opacity(0.35), radius: 4, y: 2)

                                        if theme.selectedHex.uppercased() == preset.hex.uppercased() {
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: 3)
                                                .frame(width: 38, height: 38)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }

                                    Text(preset.name)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.name)
                        }
                    }
                    .padding(.vertical, 4)

                    Divider().padding(.vertical, 4)

                    // Custom Color Picker
                    ColorPicker(selection: $customColor, supportsOpacity: false) {
                        HStack(spacing: 10) {
                            Image(systemName: "paintpalette.fill")
                                .foregroundStyle(theme.accentColor)
                                .font(.body)
                            Text("自定义调色盘")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .onChange(of: customColor) { _, newColor in
                        theme.selectCustomColor(newColor)
                    }

                    if theme.selectedHex.uppercased() != AppTheme.presets[0].hex.uppercased() {
                        Button {
                            theme.resetToDefault()
                            customColor = AppTheme.presets[0].color
                        } label: {
                            HStack {
                                Spacer()
                                Text("恢复默认翡翠绿")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.secondary)
                                Spacer()
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("主题强调色")
            } footer: {
                Text("所选颜色将实时应用到全 App 的按钮、标签、高亮及卡片装饰中。")
            }
        }
        .navigationTitle("外观与主题")
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
