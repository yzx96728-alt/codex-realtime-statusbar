#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
APP_NAME='Codex实时状态栏'
BUNDLE_ID='local.cc.codex-usage-monitor'
DIST_DIR="${DIST_DIR:-dist}"
ARCHITECTURES="${ARCHITECTURES:-arm64 x86_64}"
MACOS_MIN_VERSION="${MACOS_MIN_VERSION:-13.0}"
mkdir -p build/bin build/module-cache "$DIST_DIR/$APP_NAME.app/Contents/MacOS"
BINARIES=()
for architecture in $ARCHITECTURES; do
    case "$architecture" in arm64|x86_64) ;; *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;; esac
    swiftc -O -target "$architecture-apple-macos$MACOS_MIN_VERSION" \
        -module-cache-path "$PROJECT_ROOT/build/module-cache" \
        -framework AppKit -framework ApplicationServices -lsqlite3 \
        Sources/CPUTemperature.swift Sources/WindowState.swift Sources/main.swift Sources/Following.swift Sources/ChatPicker.swift Sources/UsageCore.swift Sources/Localization.swift \
        -o "build/bin/CCUsage-$architecture"
    BINARIES+=("build/bin/CCUsage-$architecture")
done
if [ "${#BINARIES[@]}" -gt 1 ]; then
    lipo -create "${BINARIES[@]}" -output "$DIST_DIR/$APP_NAME.app/Contents/MacOS/CCUsage"
else
    cp "${BINARIES[0]}" "$DIST_DIR/$APP_NAME.app/Contents/MacOS/CCUsage"
fi
cp Resources/Info.plist "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/Resources"
cp Resources/AppIcon.icns "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/Resources/Localization"
cp Resources/Localization/en.json "$DIST_DIR/$APP_NAME.app/Contents/Resources/Localization/en.json"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$DIST_DIR/$APP_NAME.app/Contents/Resources/"
codesign --force --sign "${SIGNING_IDENTITY:--}" --identifier "$BUNDLE_ID" "$DIST_DIR/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$DIST_DIR/$APP_NAME.app"
lipo -info "$DIST_DIR/$APP_NAME.app/Contents/MacOS/CCUsage"
echo "Built: $PROJECT_ROOT/$DIST_DIR/$APP_NAME.app"
