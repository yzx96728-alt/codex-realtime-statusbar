# Codex Live Status Bar

[简体中文](README.md) · English

<img src="Resources/icons/AppIcon.png" alt="Codex Live Status Bar icon" width="96" height="96">

A small, translucent macOS panel for local Codex chat usage. **Monitoring does not call a model or consume model tokens.** This is an independent community utility, unaffiliated with OpenAI.

## Features

- Follow the active Codex chat, or search by name and pin monitoring. Recent chats are not expanded in the menu.
- Click metrics for cumulative/latest tokens, cache-hit calculations and estimated context usage.
- Quiet 80% / 90% context alerts after a real task-completion event; no sound or input focus.
- Copy `/compact` or a handoff instruction and return to its target chat. You paste and send it.
- Hide outside Codex and refresh the target before showing again.
- Remember language, opacity, window position, alert state and the last prepared handoff source.

## Download and setup

Download `CodexRealtimeStatusbar-v1.6-macOS-universal.zip` from [Releases](https://github.com/yzx96728-alt/codex-realtime-statusbar/releases/latest), then extract the app.

1. Keep the app in a stable location, such as Applications, and launch it.
2. Open `⋯ → 语言 / Language → English`. Changes apply immediately and persist across restarts.
3. Enable **Follow current chat** and grant Accessibility permission to this copy of the app in **System Settings → Privacy & Security → Accessibility**.
4. Switch chats in Codex. `↪` means follow; `⌖` means pinned. Click any metric for details.

Chat names are preserved, not translated. Language changes do not reset monitoring or alert history. Handoff instructions follow the selected language; `/compact` stays unchanged. System-owned dialogs use the macOS language.

The universal build includes Apple Silicon and Intel code, with a macOS13 deployment target. Actual device testing uses ARM / macOS26.5.1; Intel has only been cross-compiled, not tested on an Intel Mac. Compatibility with every Codex/macOS combination is not guaranteed.

**The download has an ad-hoc signature and no Apple Developer ID notarization.** If macOS blocks it, you can review and build the source locally using the steps below without weakening system security settings. After updating, verify actual chat recognition rather than relying only on the Accessibility toggle.

## Metric definitions

| Metric | Meaning |
| --- | --- |
| Tokens | Cumulative input + output, including repeated context. Cached tokens are part of input; reasoning is part of output. Do not add these subsets again. |
| Cache | Cumulative cached input / all input. Latest-request details are also available. |
| Context≈ | Latest request’s total tokens / recorded context-window capacity. An estimate, not a live official value. |
| Account limits | Timestamped historical data from the selected chat’s usage event. Shared account usage may have changed. Not a live balance or bill. |

Existing snapshots do not trigger alerts on first observation. Only new usage records no older than two minutes can qualify. Alerts wait for a real `task_complete` event; unknown/running tasks do not count as complete. Each tier is deduplicated per chat across restarts; dropping below70% rearms it. A jump across both tiers shows only the highest current tier.

## Handoff and compact

The app only copies a command and opens the existing target chat through a Codex link. It does not modify drafts, send messages, create chats or generate summaries. **You must paste and send the command.** Codex’s subsequent processing uses normal model tokens.

Handoff requires a separately installed skill named `handoff`; personal skills are not included. The command requests verified state, confirmed decisions and permission boundaries, continuation in the original working directory, read-only verification before continuing, and preservation of the source chat. Buttons are disabled when the chat ID or original directory cannot be verified. The source bookmark does not indicate a completed handoff.

## Privacy and compatibility

Reads local `~/.codex/state_5.sqlite` and structured usage/task events in local session JSONL. Following reads only Codex’s window/header metadata, preferring a reliable chat ID or unique title. Ambiguous/missing information fails closed.

No screenshots, OCR, uploads, background model processes or new services. Settings and source bookmarks stay in local UserDefaults. Downloads and this repository contain no maintainer chats, private paths, account credentials or personal skills.

Codex’s local index/event format may change and require updates. This version does not hide specifically for internal Codex home/settings pages.

The v1.6 status-bar download is about366KB (about1MB unpacked). It is separate from **GitHub Desktop**, whose installer is hundreds of MB. GitHub Desktop does not need to run while using the status bar.

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
