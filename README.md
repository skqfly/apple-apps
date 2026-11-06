# Apple Apps

skqfly 的 Apple 平台应用仓库。每个应用独立放在 `apps/<app-name>/`，仓库级脚本放在 `scripts/`。

## 应用

| 目录 | 应用 | 状态 |
| --- | --- | --- |
| `apps/site-publisher` | Site Publisher | 开发中，用于管理并发布个人网站内容 |

新增应用时复制一个应用目录，保留自己的 Xcode 工程、源码、资源和预览脚本，不把多个应用塞进同一个 `.xcodeproj`。

## Site Publisher

四个导航栏目与网站一致：Blog、Projects、Talks、Friends。应用图标直接使用网站的四向标志。

## 构建

GitHub Actions 使用 macOS 26 和 Xcode 26.6：

1. 用网站标志渲染 1024×1024 图标。
2. 渲染导航预览。
3. 构建未签名的 iOS 26 IPA。

产物名称是 `site-publisher-ipa`。未签名 IPA 可以归档和检查，但不能直接安装到 iPhone。
