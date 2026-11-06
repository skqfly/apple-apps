# Site Publisher

iOS 26 app for publishing and reviewing content on [skqfly’s site](https://mmddskq.top).

This first version establishes the app icon and the navigation structure. It does not connect to Trilium or publish content yet.

## Navigation

The four destinations follow the public site navigation:

- Blog
- Projects
- Talks
- Friends

Publishing controls belong to the selected destination rather than becoming a fifth top-level tab. On iOS 26, the system renders the native `TabView` tab bar as Liquid Glass automatically.

## Requirements

- Xcode 26 or newer
- iOS 26 deployment target
- iPhone portrait layout for the first design pass

GitHub Actions uses the `macos-26` runner to render the icon and navigation preview with Swift, then builds the app for the iPhone 17 simulator. The rendered images are uploaded as the `site-publisher-design` artifact.

## Project layout

```text
SitePublisher.xcodeproj
Sources/SitePublisher
Resources/Assets.xcassets
```

Open `SitePublisher.xcodeproj` in Xcode and run the `SitePublisher` scheme.
