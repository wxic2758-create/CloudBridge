# CloudBridge

CloudBridge 是面向 Mac 的 SFTP 客户端，可浏览远程文件、用 Quick Look 预览并下载到本机。

[在 Mac App Store 免费获取 CloudBridge](https://apps.apple.com/us/app/cloudbridge-sftp-transfer/id6787467520?pt=128852046&ct=2026Oct_GitHub&mt=12)

## 当前状态

1.0 已在 Mac App Store 上架。当前代码支持密码连接、远程目录浏览与 Quick Look、文件和文件夹下载、下载历史、Finder 定位及系统明暗外观。保存的服务器密码使用 macOS 钥匙串；本仓库仍在迭代，开发分支功能以实际构建和测试为准。

## 打开与构建

用 Xcode 打开 `CloudBridge.xcodeproj`，选择 `CloudBridge` scheme 和 My Mac 运行。

命令行构建（产物放在项目外）：

```sh
xcodebuild -project CloudBridge.xcodeproj -scheme CloudBridge \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/CloudBridge-DerivedData CODE_SIGNING_ALLOWED=NO build
```

本地打包使用 `./build-app.sh`，会重新生成 `.build/` 和 `build/`，可用于安装包和签名验证。正式提交请使用 Xcode Archive/Export，并按 `RELEASE_CHECKLIST.md` 完成真实服务器验收和 App Store Connect 配置。

## 目录

- `Sources/CloudBridge/`：当前 SwiftUI 界面、状态模型及 SFTP 实现。
- `Tests/`：现有测试。
- `Resources/`：全部语言资源、术语和认证辅助脚本。
- `Assets/`：图标源文件、资源目录和打包图标。
- `scripts/`：本地化检查、发布检查、图标与截图生成工具。
- `website/`：现有网站与隐私页面，需在新版本发布前核对。
- `cloudbridge-product-plan.md`：产品规划。
- `PrivacyPolicy.md`：隐私政策。
- `AppStore*Options.plist`、`CloudBridge.entitlements`：导出及签名配置。

旧 HTML 原型、旧界面截图、过期交接/发布记录和本地缓存已从项目移除。Git 历史保留。

## 图标与预览

- `MainView.swift` 的 `BridgeArtwork` / `BridgeSilhouette` 定义共享矢量图形，标题栏直接绘制。
- 运行 `python3 scripts/render-brand.py` 使用 `Assets/IconComposer/CloudBridge-Purple.icon` 生成 `Assets/AppIcon-Source.png` 以及全部 macOS 图标尺寸。需要 Xcode 的 Icon Composer 工具链和 Pillow。
- 内容预览先下载临时副本：文本显示前 2 MB；图片、PDF 与影音交由系统原生预览视图。格式支持取决于系统编解码器和预览插件；不支持的文件仍可下载。
- 临时预览在关闭或替换时清理；失败下载也会清理临时目录。当前不自动为整份远程列表下载文件生成缩略图。
