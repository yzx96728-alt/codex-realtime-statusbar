# Codex Live Status Bar

**v1.7.3** restores panel visibility, distinguishes live GUI permission from CLI probes, and adds a native CPU icon with read-only temperature. See [validation and compatibility limits](docs/v1.7.3-validation.md).

[简体中文](README.md) · English

<img src="Resources/icons/AppIcon.png" alt="Codex Live Status Bar icon" width="96" height="96">

A small, translucent macOS panel for local Codex chat usage. **Monitoring does not call a model or consume model tokens.** This is an independent community utility, unaffiliated with OpenAI.

## Features

- Follow the active Codex chat, or search by name and pin monitoring. Recent chats are not expanded in the menu.
- Click metrics for cumulative/latest tokens, cache-hit calculations and estimated context usage.
- Orange context at65% with guidance on click; a prominent nonactivating handoff hint at70% after normal completion.
- Copy a handoff instruction and return to its target chat. You paste and send it.
- Hide outside Codex and refresh the target before showing again.
- Remember language, opacity, window position, alert state and the last prepared handoff source.

## Download and setup

Download `CodexRealtimeStatusbar-v1.7.3-macOS-universal.zip` from [Releases](https://github.com/yzx96728-alt/codex-realtime-statusbar/releases/latest), then extract the app.

1. Extract the complete ZIP and double-click `安装或升级.command` (Install or Upgrade). It integrates app and skill, validates backups and supports rollback. Identical skills are skipped; changes require confirmation, duplicate skills pause the update.
2. Open `⋯ → 语言 / Language → English`. Changes apply immediately and persist across restarts.
3. Enable **Follow current chat** and grant Accessibility permission to this copy of the app in **System Settings → Privacy & Security → Accessibility**.
4. Switch chats in Codex. `↪` means follow; `⌖` means pinned. Click any metric for details.

Chat names are preserved, not translated. Language changes do not reset monitoring or alert history. Handoff instructions follow the selected language. System-owned dialogs use the macOS language.

The universal build includes Apple Silicon and Intel code, with a macOS13 deployment target. Actual device testing uses ARM / macOS26.5.1; Intel has only been cross-compiled, not tested on an Intel Mac. Compatibility with every Codex/macOS combination is not guaranteed.

**The download has an ad-hoc signature and no Apple Developer ID notarization.** If macOS blocks it, you can review and build the source locally using the steps below without weakening system security settings. After updating, verify actual chat recognition rather than relying only on the Accessibility toggle.

## Metric definitions

| Metric | Meaning |
| --- | --- |
| Tokens | Cumulative input + output, including repeated context. Cached tokens are part of input; reasoning is part of output. Do not add these subsets again. |
| Cache | Cumulative cached input / all input. Latest-request details are also available. |
| Context≈ | Ordinary-request total or confirmed compaction baseline / recorded capacity. Missing or unknown data is not estimated. |
| Account limits | Timestamped historical data from the selected chat’s usage event. Shared account usage may have changed. Not a live balance or bill. |

Existing snapshots do not trigger alerts on first observation. Only new usage records no older than two minutes can qualify. Alerts wait for a real `task_complete` event; unknown/running tasks do not count as complete. Each tier is deduplicated per chat across restarts; dropping below55% rearms it. A jump across both tiers shows only the highest current tier.

## Handoff

The app only copies a command and opens the existing target chat through a Codex link. It does not modify drafts, send messages, create chats or generate summaries. **You must paste and send the command.** Codex’s subsequent processing uses normal model tokens.

The download includes the community `handoff` skill and `安装交接技能.command`, its macOS installer. Keep it beside the `skills` folder and double-click to install. It needs no Python, counters or hooks. New installs use `~/.agents/skills/handoff`; an existing legacy installation is updated in place after confirmation, with a backup outside skill discovery under `~/.codex-handoff-backups`. Multiple declared copies stop installation. If macOS blocks the script, install the included folder manually as described in [the package guide](docs/INSTALL.en.md). The command requests verified state, confirmed decisions and permission boundaries, continuation in the original working directory, read-only verification before continuing, and preservation of the source chat. Buttons are disabled when the chat ID or original directory cannot be verified. The source bookmark does not indicate a completed handoff.

## Privacy and compatibility

Reads local `~/.codex/state_5.sqlite` and structured usage/task events in local session JSONL. Following reads only Codex’s window/header metadata, preferring a reliable chat ID or unique title. Ambiguous/missing information fails closed.

No screenshots, OCR, uploads, background model processes or new services. Settings and source bookmarks stay in local UserDefaults. Downloads and this repository contain no maintainer chats, private paths, account credentials or personal settings; only generic skill source is included.

Codex’s local index/event format may change and require updates. This version does not hide specifically for internal Codex home/settings pages. Codex handles automatic compaction; the bar does not change its settings or offer a manual compact button.

The v1.7.3 download includes the app, handoff skill and installer; its exact size is shown on the release page (the app is about1MB unpacked). It is separate from **GitHub Desktop**, whose installer is hundreds of MB. GitHub Desktop does not need to run while using the status bar.

## Build

Requires macOS, Xcode Command Line Tools, Swift and system SQLite; no third-party packages.

```bash
./scripts/test.sh
./scripts/package.sh
```

Outputs go to `dist/`. For Apple Silicon only:

```bash
ARCHITECTURES=arm64 ./scripts/build.sh
```

Optional read-only checks against your own local chat catalog: `./scripts/test.sh --live-catalog`. Default tests use isolated fixtures. Finish signing before granting Accessibility access to the final build.

Icon sources live in `Resources/icons/`; `scripts/make-icon.swift` generates the standard sizes locally. PNG/SVG previews are excluded from the application bundle.

A bare `$handoff` saves progress only. Explicitly request saving, creating/opening a fresh chat in the original directory and continuing for a complete handoff. Without chat-management tools, the skill provides material and an opening prompt for manual continuation. Plan mode plans without writing or creating chats. The instruction-only skill works independently of this macOS app and follows the user’s language.

At65%, only color and click-through guidance change. At70%, fresh eligible usage and normal completion can show a handoff hint. Compaction and cancellation invalidate old hints; duplicate broadcasts do not refresh eligibility. Below55% rearms. These are heuristic thresholds, not proven optimal cost switching points.

Choose native start-at-login during installation or in the menu. Manage it in System Settings > General > Login Items (& Extensions). The running monitor waits hidden, stops refresh while hidden, and resumes when Codex is foreground. Deliberate Quit is respected. Opening Codex cannot launch a monitor that is not running. Prefer /Applications; agree explicitly to ~/Applications if needed. No automatic elevation. See [package instructions](docs/INSTALL.en.md).

## CPU temperature and upgrade consent

The menu bar shows the hottest readable CPU sensor, sampled every10 seconds. M1-family keys are supported and M1 Max is hardware-tested. Intel TC0D is attempted without hardware validation; other families currently show unavailable. Missing or stale data shows a dash. No root helper, fan writes or model calls.

On an ad-hoc upgrade, a blue Accessibility switch can still refer to an old code requirement. If live GUI trust remains denied, quit the app, remove only its old entry in System Settings > Privacy & Security > Accessibility, add the final installed app again and authenticate yourself. Reopen that same copy. No TCC database editing or relaxed signing requirements. The independent CLI probe can remain false even when the running GUI is trusted; use the live GUI status and actual following as acceptance.
