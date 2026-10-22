#!/bin/bash
set -euo pipefail

: "${KEYCHAIN:?path of the keychain to create or use}"
: "${P12_BASE64:?base64 p12}"
: "${P12_PASSWORD:?p12 password}"

KEYCHAIN_PASSWORD=${KEYCHAIN_PASSWORD:-$(uuidgen)}
P12_FILE=$(mktemp)
trap 'rm -f "$P12_FILE"' EXIT

if [[ ! -e "$KEYCHAIN" ]]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    keychains=$(security list-keychains -d user)
    existing=()
    while read -r keychain; do
        keychain=${keychain#\"}
        keychain=${keychain%\"}
        [[ -n "$keychain" ]] && existing+=("$keychain")
    done <<< "$keychains"
    security list-keychains -d user -s "$KEYCHAIN" "${existing[@]}"
fi
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

printf '%s' "$P12_BASE64" | base64 --decode > "$P12_FILE"
security import "$P12_FILE" -f pkcs12 -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
security find-identity -p codesigning "$KEYCHAIN"
