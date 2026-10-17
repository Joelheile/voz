#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION=release
if [[ "${1:-}" == "--debug" ]]; then
    CONFIGURATION=debug
    shift
fi
VERSION=${1:-}
BUILD=${2:-}

SIGNING_IDENTITY=${SIGNING_IDENTITY:-8122E8329843B07F07BD077D076ADDE0356739B3}
TIMESTAMP=${TIMESTAMP:-none}
APP=build/voz.app

BUILD_FLAGS=(-c "$CONFIGURATION")
if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_FLAGS+=(-Xswiftc -Osize)
fi

swift build "${BUILD_FLAGS[@]}"
BIN_PATH=$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_PATH/Voz" "$APP/Contents/MacOS/voz"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Library/LaunchAgents"
cp Resources/com.joelheile.voz.relaunch.plist "$APP/Contents/Library/LaunchAgents/"
if [[ -n "$VERSION" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "$BUILD" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi
ditto "$BIN_PATH/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
if [[ "$CONFIGURATION" == "release" ]]; then
    strip -x "$APP/Contents/MacOS/voz"
fi
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/voz"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
for bundle in "$BIN_PATH"/*.bundle; do
    [[ -e "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Sparkle signing order: https://sparkle-project.org/documentation/sandboxing/#code-signing
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign() { codesign --force --options runtime --timestamp="$TIMESTAMP" --sign "$SIGNING_IDENTITY" "$@"; }
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"

codesign --force --options runtime --timestamp="$TIMESTAMP" \
    --entitlements Resources/voz.entitlements \
    --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($CONFIGURATION)"
