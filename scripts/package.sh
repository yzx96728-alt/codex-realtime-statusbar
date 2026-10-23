#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
./scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
PACKAGE="CodexRealtimeStatusbar-v${VERSION}-macOS-universal.zip"
# Stage an explicit allowlist, never a local skill installation or settings.
STAGING=$(mktemp -d "$PROJECT_ROOT/build/package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
FOLDER="$STAGING/CodexRealtimeStatusbar-v${VERSION}"
mkdir -p "$FOLDER/skills/handoff/agents" "$FOLDER/skills/handoff/references"
ditto --norsrc --noextattr 'dist/Codex实时状态栏.app' "$FOLDER/Codex实时状态栏.app"
cp skills/handoff/SKILL.md "$FOLDER/skills/handoff/SKILL.md"
cp skills/handoff/agents/openai.yaml "$FOLDER/skills/handoff/agents/openai.yaml"
cp skills/handoff/references/handoff.md "$FOLDER/skills/handoff/references/handoff.md"
cp 安装交接技能.command "$FOLDER/安装交接技能.command"
cp docs/使用说明.md "$FOLDER/使用说明.md"
cp docs/INSTALL.en.md "$FOLDER/README.en.md"
ditto -c -k --keepParent --norsrc --noextattr "$FOLDER" "dist/$PACKAGE"
python3 Tests/PackageTests.py "dist/$PACKAGE"
(cd dist && shasum -a 256 "$PACKAGE" > SHA256SUMS.txt)
echo "Packaged: $PROJECT_ROOT/dist/$PACKAGE"
