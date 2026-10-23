# Codex实时状态栏 v1.7

65%首次、70%再次轻提醒，在真实任务结束后提示准备交接，为整理材料预留空间。低于55%重新允许下一轮提醒；历史首次读取不弹出，跨聊天、重启去重。升级将旧80%／90%已提示档位映射至65%／70%，清除旧待弹提醒，并以首次读取建立基线。

本版移除小窗手动压缩入口，由Codex自行处理自动压缩。随包提供轻量通用 `handoff` 技能、`安装交接技能.command` 和中英文说明，技能无需Python、计数器或Hook；有聊天管理工具时核验后接续，缺少工具时提供手动开场指令，遵守Plan模式并保留源聊天。仅输入 `$handoff` 默认只保存进度。

下载 `CodexRealtimeStatusbar-v1.7-macOS-universal.zip`，解压后在版本文件夹中取出应用使用；保持安装脚本与 `skills` 同目录后双击安装技能。已安装同名技能时先确认并完整备份，多份同名安装则停止。只想看用量可以不安装技能。下载包校验值见 `SHA256SUMS.txt`。

自动跟随、名称搜索、指标详情、简体中文／English、透明度与位置记忆仍可使用。日常监控不调用模型、不上传数据；交接入口只复制指令并返回锁定的来源聊天，由你粘贴发送。上下文为估算，账号额度为带时间的历史快照，65%／70%不是官方质量或费用分界。

通用应用包含ARM及Intel架构，最低构建目标macOS13。Intel仅交叉编译，未实机验证。应用为ad-hoc签名，无Apple Developer ID公证；更新后以最终应用的实际跟随结果检查辅助功能授权，系统认证由用户完成。不降低系统安全设置。发布包不含维护者私人路径、聊天、账号资料或本机备份。

English: v1.7 moves quiet handoff alerts to65%/70%, re-arms below55%, migrates legacy alert history and removes the manual compact shortcut. It bundles a standalone community handoff skill, a confirmation-and-backup installer, and bilingual instructions, without hooks, counters or Python dependencies. The skill verifies state before takeover, preserves the source chat, supports manual continuation when tools are missing, and respects Plan mode. The app is universal and ad-hoc signed, not notarized; Intel is cross-compiled, not hardware-tested. See README.en.md for setup and limitations.
