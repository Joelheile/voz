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
SCRATCH=.build
BUILD_FLAGS=(-c "$CONFIGURATION")
if [[ "$CONFIGURATION" == release ]]; then
    # -enable-testing differs from the app build, so a shared scratch path rebuilds every dependency.
    SCRATCH=.build/test
    BUILD_FLAGS+=(-Xswiftc -Osize -Xswiftc -enable-testing)
fi
BUILD_FLAGS+=(--scratch-path "$SCRATCH")

swift build --build-tests "${BUILD_FLAGS[@]}"
mkdir -p build
swiftc -F "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" scripts/test-host/main.swift -o build/test-host
build/test-host "$SCRATCH/$CONFIGURATION/vozPackageTests.xctest/Contents/MacOS/vozPackageTests"
