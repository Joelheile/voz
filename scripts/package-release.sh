#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?version}
BUILD=${2:?build number}
CHANNEL=${3:?stable or beta}
TAG=${4:?release tag}
NOTES=${5:?release notes file}
APPCAST=${6:-appcast.xml}
REPO=${GITHUB_REPOSITORY:-Joelheile/voz}

SIGN_UPDATE=.build/artifacts/sparkle/Sparkle/bin/sign_update
ARCHIVE=build/voz-$VERSION.zip

rm -f "$ARCHIVE"
ditto -c -k --keepParent build/voz.app "$ARCHIVE"

sign_args=(-p)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    key_file=$(mktemp)
    trap 'rm -f "$key_file"' EXIT
    printf '%s' "$SPARKLE_PRIVATE_KEY" > "$key_file"
    sign_args+=(--ed-key-file "$key_file")
fi
SIGNATURE=$("$SIGN_UPDATE" "${sign_args[@]}" "$ARCHIVE")
LENGTH=$(stat -f%z "$ARCHIVE")

python3 scripts/appcast.py "$APPCAST" "$VERSION" "$BUILD" "$CHANNEL" \
    "https://github.com/$REPO/releases/download/$TAG/voz-$VERSION.zip" \
    "$SIGNATURE" "$LENGTH" "https://github.com/$REPO/releases/tag/$TAG" "$NOTES"
echo "Packaged $ARCHIVE and updated $APPCAST"
