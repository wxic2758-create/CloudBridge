# CloudBridge

macOS SwiftUI SFTP 下载工具。当前正在重做界面。

## 当前状态

当前界面已接回服务器选择、添加/编辑、OpenSSH 首次信任、远程文件浏览与 Quick Look、顺序下载队列、重复下载自动重命名、下载历史、取消/重试、Finder 定位、下载目录及全部语言选择。已移除示例下载数据和硬编码英文，密码随应用的本机服务器配置保存，不访问 macOS 钥匙串。界面支持系统明暗外观；真实服务器端到端连接与下载仍需在目标服务器上验收。

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
