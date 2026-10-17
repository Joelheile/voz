#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks

swift build --build-tests
mkdir -p build
swiftc -F "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" scripts/test-host/main.swift -o build/test-host
build/test-host .build/debug/vozPackageTests.xctest/Contents/MacOS/vozPackageTests
