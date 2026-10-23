# Codex Live Status Bar 1.7

This download includes the universal macOS app, the community `handoff` skill, its installer, and instructions. Monitoring reads local data and does not call a model.

1. Move `Codex实时状态栏.app` to a fixed location and open it. Enable “Follow current chat” in `⋯`, then authorize this final app in System Settings → Privacy & Security → Accessibility if requested.
2. Keep `安装交接技能.command` beside the `skills` folder and double-click it to install the optional handoff skill. It requires no Python or network. If macOS blocks the downloaded script, follow the manual installation below; do not lower system security settings.
3. New installs use `~/.agents/skills/handoff`. An existing user installation, including the legacy `~/.codex/skills` or `$CODEX_HOME/skills`, is updated in place only after you confirm. The previous folder is backed up under `~/.codex-handoff-backups`, outside skill discovery. Multiple declared `handoff` skills stop the installer so you can choose which to keep.
4. Type `$handoff` in Codex. If the skill is not discovered, restart Codex. Monitoring itself works without the skill.

Manual installation: copy the included `skills/handoff` folder into `~/.agents/skills/`. Check for an existing skill first, including legacy locations; back it up outside skill directories before replacing it. Install only one copy. On other operating systems the instruction-only skill can also be installed manually in the host's supported skills directory; the app and `.command` installer are for macOS.

Click Token, Cache or Context for details. `↪` follows the current chat; `⌖` is pinned. Search, language, opacity and alert settings are in `⋯`.

Quiet handoff alerts start at 65%, then 70%, only after a real task-completion event with fresh usage. Each chat/tier is shown once across restarts; below55% re-arms the cycle. A jump across tiers shows only the highest tier. First historical reads do not alert. Context is an estimate, not an account balance, cost, or a mandatory switching threshold. Automatic compaction remains Codex's responsibility.

The handoff button copies an instruction and returns to its locked source chat. Paste and send it yourself. It does not send, create a chat, or generate a summary. A bare `$handoff` saves progress only. Explicitly request saving, creating/opening a new chat in the original directory and continuing for a complete handoff. The skill verifies material and receiver state before transferring ownership and preserves the source chat. If chat-management tools are missing, it provides material and an opening prompt for manual continuation. In Plan mode it plans without writing or creating chats. It has no hooks, counters or background reminder service.

Language, opacity, position, follow/pinned selection, and source bookmark are preserved on upgrade. Legacy80%/90% alert history maps to65%/70%; pending alerts are cleared and the first upgraded read establishes a baseline. Account limits are timestamped session snapshots; cache and reasoning tokens are subdivisions, not added twice.

The app targets macOS13+, includes ARM and Intel, and is ad-hoc signed without Developer ID notarization. Intel is cross-compiled, not hardware-tested. No screenshots, OCR, uploads, background models or private maintainer files are included. Verify the zip with the published `SHA256SUMS.txt`.

Source and updates: https://github.com/yzx96728-alt/codex-realtime-statusbar
