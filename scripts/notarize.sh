#!/bin/bash
set -euo pipefail

# Notarizes and staples a signed app or disk image with an App Store Connect API key.
# Pass the app as voz.app; the script zips it for upload and staples the app itself.

TARGET=${1:?app or dmg to notarize}
: "${NOTARY_KEY:?contents of the App Store Connect API key (.p8)}"
: "${NOTARY_KEY_ID:?App Store Connect API key ID}"
: "${NOTARY_ISSUER_ID:?App Store Connect issuer ID}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(umask 077; printf '%s\n' "$NOTARY_KEY" > "$work/key.p8")

upload=$TARGET
if [[ -d "$TARGET" ]]; then
    upload="$work/$(basename "$TARGET").zip"
    ditto -c -k --keepParent "$TARGET" "$upload"
fi

result=$(xcrun notarytool submit "$upload" \
    --key "$work/key.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
    --wait --timeout 30m --output-format json)
id=$(plutil -extract id raw - <<< "$result")
status=$(plutil -extract status raw - <<< "$result")
if [[ "$status" != Accepted ]]; then
    echo "Notarization of $TARGET ended as $status" >&2
    xcrun notarytool log "$id" --key "$work/key.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" >&2 || true
    exit 1
fi

xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "Notarized and stapled $TARGET"
