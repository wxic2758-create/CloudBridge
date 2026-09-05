# CloudBridge Claude 交接文档

更新时间：2026-09-06

## 项目定位

CloudBridge 是 macOS 14+ 的本地优先 SSH/SFTP 远程下载客户端。核心闭环是：连接服务器 -> 浏览远程目录 -> Quick Look 预览 -> 下载到本机 -> 在 Finder 中显示。

产品显示名：`CloudBridge: SFTP Transfer`
可执行文件名：`CloudBridge`
Bundle ID：`com.dazhang.CloudBridge`
GitHub：`https://github.com/wxic2758-create/CloudBridge`

不要因为 SEO 改名而修改可执行文件名、Bundle ID、Keychain service 或已有远程历史。

## 当前已完成

- GitHub 私有仓库连接和持续推送
- SSH 主机指纹首次确认、变更阻止、专用 known_hosts
- 密码认证、Keychain 保存密码
- SSH 私钥路径选择、加密私钥密码短语、路径校验
- SFTP 浏览，失败时 legacy SSH/SCP fallback
- 文件/文件夹下载、取消、失败、重试
- 下载冲突策略 API：rename（默认）、replace、skip
- Quick Look 临时文件清理
- ProcessRunner：持续 drain stdout/stderr、取消、超时、增量输出回调
- SwiftPM 测试 target；当前 5 个测试全部通过
- Xcode 工程已包含 ProcessRunner.swift
- Xcode 和手工 build 脚本都会打包 36 个 locale（另有 zh-Hans 兼容目录）
- 产品元数据、术语库、locale manifest、CI 本地化 key/占位符检查
- 已完成实际译文：en、zh-TW、ja、ko、es-ES、es-MX、pt-BR、pt-PT
- 其他语言暂时英文 fallback

## 最近提交

`dbdaa52` 设置优化后的 app 显示名
`d410c36` 手工 app 构建复制本地化资源
`a6cae0d` ProcessRunner 运行中读取输出
`c40ea2e` 暴露进程输出回调
`9b09018` 下载任务增加进度指标字段

## 当前最大未完成项

### P0：真实下载进度

`DownloadTask` 已有 `progress`、`bytesTransferred`、`totalBytes`、`speedBytesPerSecond`、`estimatedRemainingSeconds` 字段，但还没有真实生产数据。

下一步应：

1. 在 `SFTPClient` 的下载命令中移除会隐藏进度的 quiet 行为，并传入输出回调。
2. 解析 OpenSSH sftp/scp 的进度行，处理 `\r` 覆盖式输出、未知总大小和目录下载。
3. 将回调安全地转发到 `BrowserModel` 的主 actor，更新对应任务。
4. 在任务面板显示百分比、速度和剩余时间；未知总大小时显示 indeterminate progress。
5. 增加进度解析单元测试、取消中断测试和异常输出测试。

### P1：下载任务体验

- 多选远程项目和批量下载
- 串行下载队列，随后再增加并发数设置
- 冲突策略接入 UI（当前只有 API）
- Finder 显示、按任务查看错误详情
- 断点续传和校验摘要

### P1：国际化

全局规则见 `/Users/user/.codex/skills/global-localization/SKILL.md`。本项目资源和规范位于 `Resources/Localization/`。

完整 locale 清单在 `locale-manifest.json`，共 36 个：`en`、`sk`、`pl`、`sv`、`he`、`ms`、`da`、`no`、`el`、`ca`、`cs`、`ro`、`zh-CN`、`uk`、`hr`、`hu`、`nl`、`fi`、`id`、`vi`、`ja`、`it`、`ru`、`zh-TW`、`ar`、`hi`、`de`、`ko`、`th`、`tr`、`es-ES`、`es-MX`、`fr-CA`、`fr-FR`、`pt-BR`、`pt-PT`。

用户要求：优先完成西班牙、葡萄牙、英文、繁体中文、日语、韩语；其他语言默认英文。不要把英文 fallback 标记为 native-reviewed。当前可标记的最高状态是 `ai-reviewed`。

长期要求：使用稳定语义 key，不要继续用中文显示文本作为 key；使用 ICU/CLDR 处理复数、日期、数字、排序和 RTL；`ar`、`he` 必须做 RTL 视觉检查。

### P1：错误恢复和可访问性

- 连接超时展示主机、端口、原因，并提供重试/编辑连接
- 完整键盘操作和 VoiceOver 标签
- 长文本、中文文件名、特殊字符、大文件、断网、权限失效测试

## 产品元数据与 SEO

真源：`Resources/Localization/ProductMetadata.md`

英文搜索短语（100 字符以内）：

`SFTP file transfer,SSH download manager,remote server files,macOS file download,server preview`

中文搜索短语：

`SFTP文件传输,SSH远程下载,远程服务器文件,macOS下载管理,服务器文件预览`

搜索元数据使用完整短语，不要退回单词堆叠。产品名与关键词需同步 App Store Connect 资料、网站和发布文档。

## 常用验证命令

```bash
swift test
swift build -c release
python3 scripts/check-localization.py
./build-app.sh
xcodebuild -project CloudBridge.xcodeproj -scheme CloudBridge -configuration Release -derivedDataPath /tmp/CloudBridgeDerived build CODE_SIGNING_ALLOWED=NO
```

`build-app.sh` 会生成 `build/CloudBridge.app` 并签名。不要提交 `build/` 生成物，除非用户明确要求。

推送时使用进程级代理，不要修改全局 Git 配置：

```bash
HTTPS_PROXY=http://127.0.0.1:15236 HTTP_PROXY=http://127.0.0.1:15236 GIT_HTTP_VERSION=HTTP/1.1 git push origin main
```

## 工作约束

- 不使用 `git reset --hard`、force push 或覆盖远程历史。
- 不提交密码、私钥内容、Keychain 数据或用户服务器信息。
- 修改后必须运行与风险匹配的测试；下载/传输层改动至少跑 `swift test` 和 Release build。
- 保持中文沟通；完成一个完整可验证阶段后再汇报，不要只提交未接通的 UI 假进度。
