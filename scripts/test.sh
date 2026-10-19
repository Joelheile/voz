#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
if [[ "$DEVELOPER_DIR" == */CommandLineTools ]]; then
    FRAMEWORKS=$DEVELOPER_DIR/Library/Developer/Frameworks
else
    FRAMEWORKS=$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks
fi

swift build --build-tests
mkdir -p build
swiftc -F "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" scripts/test-host/main.swift -o build/test-host
build/test-host .build/debug/vozPackageTests.xctest/Contents/MacOS/vozPackageTests
