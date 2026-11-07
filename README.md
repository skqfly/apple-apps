# Apple Apps

个人 Apple 应用合集。各应用放在 `apps/<name>/`，独立 Xcode 工程，构建脚本放在 `scripts/`。本地只编辑代码，编译、归档与模拟器验证由 GitHub Actions 完成。

## 栖页 · Qiye

工程：`apps/qiye/Qiye.xcodeproj`，Scheme `Qiye`，Bundle ID `top.mmddskq.qiye`。

iOS 17 起运行；用 Xcode 26.6 构建，在 iOS 26 及以上使用原生 Liquid Glass 导航。应用背景、卡片、文字和强调色同时提供浅色、深色配置，默认跟随系统，也能在个人区设置。

- **首页**：网站照片概览、照片入口和最近说说，内容来自网站真实数据。
- **博客**：保留入口，编辑功能待实现。
- **说说**：读取网站原 `talks` 分享内容。
- **照片**：网站照片网格、离线缩略图、全屏查看、本机相册导入、本机草稿保存和删除。
- **右上角个人区**：GitHub 令牌身份验证、退出登录、外观与默认作者设置、作品和友链入口。令牌只放设备钥匙串，不写入源码或 UserDefaults。

照片导入当前仅保存本机，不会发布或修改网站。GitHub 登录只验证身份，Trilium 发布流程尚未接入。

## 网站来源

图标来自 `skqfly/skqfly.github.io/public/logo.svg`，完整原始 SVG 位于 `Resources/Brand/logo.svg`。照片和说说的初始数据来自网站仓库，在前台可刷新；App 不改动网站仓库。

## GitHub Actions 产物

`qiye-build` 包含：

- `Qiye-unsigned.ipa`：设备归档产生的未签名 IPA，需自行签名后安装。
- `home-light.png`、`home-dark.png`、`photos-light.png`、`photos-dark.png`：iOS 模拟器中运行实际 SwiftUI 界面的截图。
- `account-dark.png`：个人区截图。
- `AppIcon.png`：使用原始网站标志转换的应用图标。

新 App 应使用独立目录、Scheme、Bundle ID 和构建 job，避免与栖页共用内容或凭据。
