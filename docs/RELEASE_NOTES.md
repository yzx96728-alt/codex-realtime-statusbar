# Codex实时状态栏 v1.6

轻巧半透明的 Codex 本地用量浮窗，日常监控不调用模型。

本版新增中文 / English 切换（⋯ → 语言 / Language），立即生效并记住选择；加入独立应用图标；移除菜单中展开的最近聊天列表，保留名称搜索备用入口。自动跟随逻辑保持不变。

- 自动跟随聊天，点击查看 token、缓存命中及上下文估算。
- 80%/90% 上下文提醒，等待真实任务结束后提示。
- 复制压缩或交接指令并返回目标聊天，由你粘贴发送。
- 离开 Codex 自动隐藏；透明度、位置和提醒状态会保存。

下载 `CodexRealtimeStatusbar-v1.6-macOS-universal.zip`（约366KB），解压后得到 `Codex实时状态栏.app`（约1MB）。包含 Apple Silicon 和 Intel 架构，最低构建目标为 macOS13；实际验证为 ARM / macOS26.5.1，Intel尚未实机验证。此前数百MB的安装包属于独立的 GitHub Desktop，状态栏运行不需要它。

首次使用在“系统设置 → 隐私与安全性 → 辅助功能”授权最终应用，再开启自动跟随。发布包为本地 ad-hoc 签名，没有 Apple Developer ID 公证；若系统阻止打开，可按 README 在本机从源码构建，无需降低系统安全设置。

账号额度来自历史会话快照，上下文为估算，不是实时余额或硬性换聊天判断。交接功能需自行安装 `handoff` 技能。

源码、完整说明与构建方法见项目首页；`SHA256SUMS.txt` 提供下载包校验值。发布包不含维护者聊天记录、私人路径、账号授权或个人技能。

English: This release adds a persistent Chinese / English language selector, an app icon, and a simpler menu without an expanded recent-chat list. Automatic following and name search remain available. The download is about366KB (about1MB unpacked). Monitoring uses no model tokens. The universal build targets macOS13 or later; only Apple Silicon on macOS26.5.1 has been tested on hardware. The app is ad-hoc signed, without Developer ID notarization. See README.en.md for setup and limitations.
