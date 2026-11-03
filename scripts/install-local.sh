#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=/Applications/voz.app
STAGING=/Applications/.voz-staging.app
PREVIOUS=/Applications/.voz-previous.app

scripts/make-app.sh "$@"

pkill -x voz || true
for _ in $(seq 1 50); do
    pgrep -x voz >/dev/null || break
    sleep 0.1
done

rm -rf "$STAGING" "$PREVIOUS"
ditto build/voz.app "$STAGING"
[[ -d "$APP" ]] && mv "$APP" "$PREVIOUS"
mv "$STAGING" "$APP"
rm -rf "$PREVIOUS"

codesign --verify --deep --strict "$APP"
open "$APP"
echo "Installed $APP"
