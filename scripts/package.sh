#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
./scripts/build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
PACKAGE="CodexRealtimeStatusbar-v${VERSION}-macOS-universal.zip"
# Distribute only the generic bundle. Do not package local settings or session files.
ditto -c -k --keepParent --norsrc --noextattr 'dist/Codex实时状态栏.app' "dist/$PACKAGE"
(cd dist && shasum -a 256 "$PACKAGE" > SHA256SUMS.txt)
echo "Packaged: $PROJECT_ROOT/dist/$PACKAGE"
