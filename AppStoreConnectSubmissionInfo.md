# CloudBridge App Store Connect Submission Info

Use this file as the source text when filling App Store Connect.

## App Information

- Default app name: CloudBridge: SFTP Transfer
- Bundle ID: com.dazhang.CloudBridge
- SKU: cloudbridge-macos
- Primary category: Developer Tools
- Secondary category: Utilities
- Content rights: No third-party content
- Age rating: 4+
- Price: Free for first release
- Availability: United States only for the first release

## Chinese Metadata

### App Name

CloudBridge - SFTP下载管理

### Subtitle

远程文件下载与预览

### Promotional Text

连接你自己的 SSH / SFTP 服务器，集中处理远程文件下载、文件夹拉取和 Quick Look 预览。密码仅在当前会话临时缓存。

### Description

CloudBridge 是一款面向 macOS 的轻量远程下载管理工具，适合需要从云服务器、开发机或运维主机稳定拉取文件的开发者与运维用户。

你可以输入自己的服务器 IP 或主机名、端口、用户名和密码，连接后浏览远程目录，查看文件大小与修改时间，双击文件即可使用 Quick Look 预览，并把文件或整个文件夹下载到本机指定目录。

CloudBridge 不提供账号系统，也不会把密码持久保存到 Keychain、UserDefaults 或开发者服务器。输入的密码只在当前 app 会话中临时用于连接，适合从远程主机下载日志、构建产物、配置文件和文档。

主要功能：
- 连接用户自己的 SFTP/SSH 服务器
- 支持密码登录
- 密码仅在当前会话临时缓存
- 浏览远程目录、进入文件夹、返回上级目录
- 文件双击 Quick Look 预览
- 文件和文件夹下载到本机指定目录
- 目录大小显示为 -，避免误导为固定 4 KB

CloudBridge 不提供云存储服务，也不会把用户的服务器地址、用户名、密码或文件内容发送给开发者服务器。连接目标由用户自己输入和控制。

### Keywords

SFTP文件传输,SSH远程下载,远程服务器文件,macOS下载管理,服务器文件预览

### Support URL

https://wxic2758-create.github.io/cloudbridge-pages/support.html

### Marketing URL

https://wxic2758-create.github.io/cloudbridge-pages/

### Privacy Policy URL

https://wxic2758-create.github.io/cloudbridge-pages/privacy.html

## English Metadata

### App Name

CloudBridge: SFTP Downloads

### Subtitle

Remote Download Manager

### Promotional Text

Connect to your own SSH and SFTP servers to browse remote files, preview documents with Quick Look, and pull down files or folders to your Mac. Passwords are kept only for the current app session.

### Description

CloudBridge is a lightweight macOS remote download manager for developers, operators, and power users who regularly pull files from their own SSH and SFTP servers.

Enter your server IP address or host name, port, username, and password to connect, browse remote folders, inspect file details, preview files with Quick Look, and download files or folders to a local directory on your Mac.

CloudBridge does not include an account system and does not store passwords in Keychain, UserDefaults, or a developer backend. The password you enter is kept only for the current app session and is used to connect to the server you choose. It works well for downloading logs, build artifacts, media files, project bundles, and server-side documents.

Features:
- Connect to user-provided SFTP/SSH servers
- Password-based SFTP connection
- Session-only password cache
- Browse remote server folders
- Preview files with Quick Look
- Download files and folders to a chosen local folder
- Show directory size as - to avoid misleading fixed-size values

CloudBridge is not a cloud storage service. It does not send your server address, username, password, or file contents to the developer. You choose and control the servers you connect to.

### Keywords

SFTP file transfer,SSH download manager,remote server files,macOS file download,server file preview

## App Review Information

### Contact

Use your App Store Connect account contact details.

### Demo Account

No demo account is required. CloudBridge connects only to servers provided by the user.

### Review Notes

CloudBridge is a macOS SFTP client. It does not include a hosted backend or developer-operated server. Users enter their own server IP/host, port, username, password, and remote path.

The app can be reviewed without a developer-provided account by using any standard SSH/SFTP test server owned by the reviewer. CloudBridge does not store passwords in Keychain or UserDefaults; the entered password remains only in the current app session and is used to establish the user-requested SSH/SFTP connection.

Double-clicking a remote file downloads a temporary preview copy and opens it with macOS Quick Look. Explicit downloads are saved to the user-selected local download folder.

Network access is used only to connect to user-provided SSH/SFTP servers.

CloudBridge is sandboxed. For download testing, choose the target download folder with the in-app folder picker; CloudBridge stores an app-scoped security bookmark for the selected download folder.

## App Privacy Answers

Recommended answer: Data Not Collected.

Reasoning: CloudBridge does not collect data for the developer, does not use analytics, does not use ads, does not use tracking, and does not send user data to a developer backend. The user may enter server connection details and a password, but passwords are not stored persistently and are used only to connect to the user-specified server during the current app session.

If App Store Connect asks about specific data types:
- Contact Info: Not collected
- Identifiers: Not collected
- Usage Data: Not collected
- Diagnostics: Not collected, unless you later enable Apple crash reports or third-party crash reporting
- User Content: Not collected by the developer
- Other Data: Not collected
- Tracking: No

Important wording for privacy review:

CloudBridge keeps the entered password only in the current app session. The app transmits credentials only to the server address entered by the user in order to establish the SFTP/SSH connection. The developer does not receive or collect this data.

## Encryption Export Compliance

CloudBridge uses SSH/SFTP/SCP behavior through standard macOS system tooling and standard SSH encryption for user-initiated connections to user-provided servers.

Suggested App Store Connect answers:
- Does your app use encryption? Yes.
- Is the encryption limited to Apple operating system functionality or standard system-provided secure networking/SSH behavior? Yes, based on the current implementation using macOS system tools.
- Does the app implement proprietary or non-standard encryption? No.
- Does the app provide general-purpose encryption features to users? No.

If App Store Connect asks for documentation, follow the generated instructions in App Store Connect. Based on Apple's guidance, apps using encryption limited to Apple operating system functionality typically do not need additional export compliance documentation.

## Screenshots

Mac screenshots are required. Apple currently accepts Mac screenshots with a 16:10 aspect ratio at these sizes:

- 1280 x 800
- 1440 x 900
- 2560 x 1600
- 2880 x 1800

Upload at least 1 and up to 10 screenshots.

Recommended screenshot set:
- Main connection screen
- Connected remote folder browser
- Quick Look file preview
- Local download folder selection or completed download state

Do not use screenshots containing real private server IPs, usernames, passwords, tokens, filenames, or customer data. Use a test server or redact private values before uploading.

## Version Information

- Version: 0.1.0
- Build: 6
- What's New:

Initial release of CloudBridge for macOS: connect to your own SFTP server, browse remote folders, preview files with Quick Look, and download files or folders.
