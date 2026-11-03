#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make-app.sh --debug "$@"
pkill -x voz || true
sleep 0.5
open build/voz.app
