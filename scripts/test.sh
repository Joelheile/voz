#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
if [[ "$DEVELOPER_DIR" == */CommandLineTools ]]; then
    FRAMEWORKS=$DEVELOPER_DIR/Library/Developer/Frameworks
else
    FRAMEWORKS=$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks
fi

CONFIGURATION=${1:-debug}
case "$CONFIGURATION" in
    debug|release) ;;
    *) echo "usage: scripts/test.sh [debug|release]" >&2; exit 64 ;;
esac
BUILD_FLAGS=(-c "$CONFIGURATION")
if [[ "$CONFIGURATION" == release ]]; then
    BUILD_FLAGS+=(-Xswiftc -Osize)
fi

swift build --build-tests "${BUILD_FLAGS[@]}"
mkdir -p build
swiftc -F "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" scripts/test-host/main.swift -o build/test-host
build/test-host ".build/$CONFIGURATION/vozPackageTests.xctest/Contents/MacOS/vozPackageTests"
