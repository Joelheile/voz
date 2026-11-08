#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION=release
APP=build/voz.app
TEST_BUILD=false
if [[ "${1:-}" == "--test" ]]; then
    # Debug app with its own bundle ID, data and permissions. Never ships.
    CONFIGURATION=debug
    TEST_BUILD=true
    APP=build/voz-test.app
    shift
fi
if [[ "${1:-}" == "--debug" ]]; then
    CONFIGURATION=debug
    shift
fi
VERSION=${1:-}
BUILD=${2:-}

# Releases and local installs share the Developer ID signature, so macOS keeps permissions across updates
SIGNING_IDENTITY=${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*) \([0-9A-F]\{40\}\) .*G2CSKBA739.*/\1/p' | head -1)}
[[ -n "$SIGNING_IDENTITY" ]] || { echo "No Developer ID Application identity for team G2CSKBA739. Set SIGNING_IDENTITY." >&2; exit 1; }
TIMESTAMP=${TIMESTAMP:-none}

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
if [[ "$TEST_BUILD" == true ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.joelheile.voz.test" -c "Set :CFBundleName Voz Test" -c "Set :CFBundleDisplayName Voz Test" "$APP/Contents/Info.plist"
fi
if [[ -n "$VERSION" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "$BUILD" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi
ditto "$BIN_PATH/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
rm -rf "$SPARKLE/XPCServices" "$SPARKLE/Headers" "$SPARKLE/PrivateHeaders" "$SPARKLE/Modules"
find "$SPARKLE/Resources" -maxdepth 1 -name '*.lproj' ! -name 'Base.lproj' ! -name 'de.lproj' -exec rm -rf {} +
rm -f "$APP/Contents/Frameworks/Sparkle.framework"/{XPCServices,Headers,PrivateHeaders,Modules}
if [[ "$CONFIGURATION" == "release" ]]; then
    rm -rf build/voz.dSYM
    dsymutil "$APP/Contents/MacOS/voz" -o build/voz.dSYM
    strip -x "$APP/Contents/MacOS/voz"
fi
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/voz"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
cp -R Resources/Extensions "$APP/Contents/Resources/Extensions"
cp -R skills/voz-extension "$APP/Contents/Resources/Extensions/voz-extension"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
python3 scripts/third-party-notices.py "$APP/Contents/Resources/ThirdPartyNotices.txt"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png CHANGELOG.md "$APP/Contents/Resources/"
for bundle in "$BIN_PATH"/*.bundle; do
    [[ -e "$bundle" && "$bundle" != *FluidAudio_FluidAudio.bundle ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Sparkle signing order: https://sparkle-project.org/documentation/sandboxing/#code-signing
sign() { codesign --force --options runtime --timestamp="$TIMESTAMP" --sign "$SIGNING_IDENTITY" "$@"; }
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"

codesign --force --options runtime --timestamp="$TIMESTAMP" \
    --entitlements Resources/voz.entitlements \
    --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# macOS ties every permission grant to this requirement. If it changes, updated installs lose their grants.
SHIPPED_REQUIREMENT='designated => identifier "com.joelheile.voz" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = G2CSKBA739'
if [[ "$TEST_BUILD" == false ]]; then
    requirement=$(codesign -d -r- "$APP" 2>&1 | grep '^designated')
    [[ "$requirement" == "$SHIPPED_REQUIREMENT" ]] || { echo "Signature requirement changed, so updates would lose permissions: $requirement" >&2; exit 1; }
fi
echo "Built $APP ($CONFIGURATION)"
