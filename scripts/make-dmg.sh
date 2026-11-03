#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT=${1:-build/voz.dmg}
APP=build/voz.app
SIGNING_IDENTITY=${SIGNING_IDENTITY:-8122E8329843B07F07BD077D076ADDE0356739B3}
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
