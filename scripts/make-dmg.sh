#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT=${1:-build/voz.dmg}
APP=build/voz.app
# Releases and local installs share the Developer ID signature, so macOS keeps permissions across updates
SIGNING_IDENTITY=${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*) \([0-9A-F]\{40\}\) .*G2CSKBA739.*/\1/p' | head -1)}
[[ -n "$SIGNING_IDENTITY" ]] || { echo "No Developer ID Application identity for team G2CSKBA739. Set SIGNING_IDENTITY." >&2; exit 1; }
TIMESTAMP=${TIMESTAMP:-none}

[[ -d "$APP" ]] || { echo "Run scripts/make-app.sh first" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swift scripts/make-dmg-background.swift Resources/Fonts "$work/background.tiff"
rm -f "$OUTPUT"
pipx run --spec dmgbuild==1.6.7 dmgbuild -s scripts/dmg-settings.py \
    -D app="$APP" -D background="$work/background.tiff" Voz "$OUTPUT"
codesign --force --timestamp="$TIMESTAMP" --sign "$SIGNING_IDENTITY" "$OUTPUT"
codesign --verify --strict "$OUTPUT"
echo "Built $OUTPUT"
