# Apple Apps

个人 Apple 应用合集。每个 App 独立放在 `apps/<name>/`，共享脚本在 `scripts/`。本地编辑代码，编译、模型验证、归档与模拟器截图均在 GitHub Actions 执行。

## 栖页 · Qiye

工程 `apps/qiye/Qiye.xcodeproj`，Scheme `Qiye`，Bundle ID `top.mmddskq.qiye`。支持 iOS 17+；Xcode 26.6 构建，在 iOS 26+ 使用系统 Liquid Glass 导航。背景与文字跟随明暗设置。

- 首页：网站 HTTP 状态、最近 GitHub 工作流、近一年贡献日历。公开贡献无需登录；仓库与工作流使用授权 API。
- 博客：从 GitHub 读取文章，搜索和原生 Markdown 阅读。内置当前文章快照供首次离线打开；公开文章索引由网站构建/Trilium 同步维护。
- 说说：从仓库读取，登录后可新建文本说说并原子提交到 main。
- 照片：纯图片墙、离线缩略图、本机导入和预览，确认后提交照片与相册 JSON；原图保留在本机。
- 个人中心：GitHub 官方设备授权，无需粘贴私人 token；网站、发布、外观分别进入二级页面。授权凭据仅放设备钥匙串。

发布成功代表 GitHub 接受了提交；网站需等待 Pages 构建部署。失败或结果不确定会明确提示，不自动重复提交。App 不内置私人令牌或 Client Secret。

## 网站与 Trilium 的职责

网站仓库 `skqfly/skqfly.github.io`，域名 `mmddskq.top`。Trilium 只管理博客文章与文章图片，保留文章发布、下架及同步日志。说说、相册、友链、项目和站点设置不再由旧 Trilium 快照覆盖。

网站的照片 `alt` 用于无障碍描述，不显示图片下方的图注。应用图标直接转换网站原始 `public/logo.svg`，全不透明方图由 iOS 裁圆角。

## 云端验证和产物

`qiye-build` 包含未签名 `Qiye-unsigned.ipa`、首页/博客/说说/照片明暗截图、个人区截图与图标。安装需自行签名。

模型验证检查贡献 tooltip 次数、不完整日历、重复日期、闰年范围、工作流状态以及文章 frontmatter/封面路径。编译和模拟器启动不等于真人 OAuth 登录或生产发布验收；这些仍需签名安装后按实际账户验证。
