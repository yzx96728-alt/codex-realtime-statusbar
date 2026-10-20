#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
APP_NAME='Codex实时状态栏'
BUNDLE_ID='local.cc.codex-usage-monitor'
ARCHITECTURES="${ARCHITECTURES:-arm64 x86_64}"
MACOS_MIN_VERSION="${MACOS_MIN_VERSION:-13.0}"
mkdir -p build/bin build/module-cache "dist/$APP_NAME.app/Contents/MacOS"
BINARIES=()
for architecture in $ARCHITECTURES; do
    case "$architecture" in arm64|x86_64) ;; *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;; esac
    swiftc -O -target "$architecture-apple-macos$MACOS_MIN_VERSION" \
        -module-cache-path "$PROJECT_ROOT/build/module-cache" \
        -framework AppKit -framework ApplicationServices -lsqlite3 \
        Sources/main.swift Sources/Following.swift Sources/ChatPicker.swift Sources/UsageCore.swift \
        -o "build/bin/CCUsage-$architecture"
    BINARIES+=("build/bin/CCUsage-$architecture")
done
if [ "${#BINARIES[@]}" -gt 1 ]; then
    lipo -create "${BINARIES[@]}" -output "dist/$APP_NAME.app/Contents/MacOS/CCUsage"
else
    cp "${BINARIES[0]}" "dist/$APP_NAME.app/Contents/MacOS/CCUsage"
fi
cp Resources/Info.plist "dist/$APP_NAME.app/Contents/Info.plist"
codesign --force --sign - --identifier "$BUNDLE_ID" "dist/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "dist/$APP_NAME.app"
lipo -info "dist/$APP_NAME.app/Contents/MacOS/CCUsage"
echo "Built: $PROJECT_ROOT/dist/$APP_NAME.app"
