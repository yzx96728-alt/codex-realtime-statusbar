#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
mkdir -p build/tests build/module-cache
# Keep assertions enabled: tests deliberately compile without -O.
swiftc -module-cache-path "$PROJECT_ROOT/build/module-cache" \
    -framework AppKit -framework ApplicationServices -lsqlite3 \
    Sources/Following.swift Sources/UsageCore.swift Sources/Localization.swift Tests/CoreTests.swift -o build/tests/core-tests
build/tests/core-tests
swiftc -module-cache-path "$PROJECT_ROOT/build/module-cache" \
    -framework AppKit -framework ApplicationServices -lsqlite3 \
    Sources/Following.swift Sources/Localization.swift Tests/FollowTests.swift -o build/tests/follow-tests
build/tests/follow-tests "$@"
swiftc -module-cache-path "$PROJECT_ROOT/build/module-cache" \
    -framework AppKit -framework ApplicationServices -lsqlite3 \
    Sources/Following.swift Sources/UsageCore.swift Sources/Localization.swift Tests/LocalizationTests.swift -o build/tests/localization-tests
build/tests/localization-tests
