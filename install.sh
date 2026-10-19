#!/bin/bash
set -euo pipefail

REPO=Joelheile/voz
APP=/Applications/voz.app
LAUNCH_AGENT=com.joelheile.voz.relaunch

fail() {
    echo "$1" >&2
    exit 1
}

main() {
    [[ "$(uname -m)" == arm64 ]] || fail "voz needs a Mac with Apple Silicon."
    (( $(sw_vers -productVersion | cut -d. -f1) >= 26 )) || fail "voz needs macOS 26 or later."

    local url
    url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
        grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4)
    [[ -n "$url" ]] || fail "No voz release found at github.com/$REPO/releases."

    local work
    work=$(mktemp -d)
    trap "rm -rf '$work'" EXIT

    echo "Downloading $url"
    curl -fL --progress-bar "$url" -o "$work/voz.zip"
    ditto -x -k "$work/voz.zip" "$work"
    codesign --verify --deep --strict "$work/voz.app"

    launchctl bootout "gui/$(id -u)/$LAUNCH_AGENT" 2>/dev/null || true
    pkill -x voz || true
    for _ in $(seq 1 50); do
        pgrep -x voz >/dev/null || break
        sleep 0.1
    done

    rm -rf "$APP"
    ditto "$work/voz.app" "$APP"
    open "$APP"
    echo "Installed voz. Finish setup from the menu bar."
}

main
