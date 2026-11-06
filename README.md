# Apple Apps

skqfly 的 Apple 平台应用仓库。每个应用独立放在 `apps/<app-name>/`，共用脚本放在 `scripts/`。

## 应用

| 目录 | 应用 | 状态 |
| --- | --- | --- |
| `apps/site-publisher` | Site Publisher | 开发中，用于管理并发布个人网站内容 |

新增应用时建立独立目录和独立 Xcode 工程，不把多个应用放进同一个工程。

## Site Publisher

导航栏目与网站一致：Blog、Projects、Talks、Friends。应用图标使用个人网站仓库中的原始 `public/logo.svg`，不重新绘制。

## 构建

GitHub Actions 使用 macOS 26 与 Xcode 26.6，构建未签名的 iOS 26 IPA。产物名称是 `site-publisher-ipa`；未签名包不能直接安装到 iPhone。
