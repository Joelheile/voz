#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make-app.sh --debug "$@"
launchctl bootout "gui/$(id -u)/com.joelheile.voz.relaunch" 2>/dev/null || true
pkill -x voz || true
sleep 0.5
open build/voz.app
