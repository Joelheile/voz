#!/bin/bash
set -euo pipefail

REPO=Joelheile/voz
APP=/Applications/voz.app
LAUNCH_AGENT=com.joelheile.voz.relaunch

fail() {
    echo "$1" >&2
    exit 1
}

step() {
    local label=$1
    shift
    if [[ ! -t 1 ]]; then
        echo "$label"
        "$@" || fail "$label failed."
        return
    fi
    "$@" &
    local pid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%s %s' "${frames:i++%${#frames}:1}" "$label"
        sleep 0.08
    done
    wait "$pid" || { printf '\r\033[K'; fail "$label failed."; }
    printf '\r\033[K✓ %s\n' "$label"
}

download() {
    curl -fsSL "$1" -o "$2/voz.zip" &&
        ditto -x -k "$2/voz.zip" "$2" &&
        codesign --verify --deep --strict "$2/voz.app"
}

install_app() {
    launchctl bootout "gui/$(id -u)/$LAUNCH_AGENT" 2>/dev/null || true
    pkill -x voz || true
    for _ in $(seq 1 50); do
        pgrep -x voz >/dev/null || break
        sleep 0.1
    done
    rm -rf "$APP" && ditto "$1/voz.app" "$APP"
}

open_and_wait() {
    open "$APP" || return 1
    local steady=0
    for _ in $(seq 1 100); do
        if pgrep -x voz >/dev/null; then
            (( ++steady >= 10 )) && return 0
        else
            steady=0
        fi
        sleep 0.2
    done
    return 1
}

main() {
    [[ "$(uname -m)" == arm64 ]] || fail "Voz needs a Mac with Apple Silicon."
    (( $(sw_vers -productVersion | cut -d. -f1) >= 26 )) || fail "Voz needs macOS 26 or later."

    local url
    url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
        grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4)
    [[ -n "$url" ]] || fail "No Voz release found at github.com/$REPO/releases."

    local work
    work=$(mktemp -d)
    trap "rm -rf '$work'" EXIT

    step "Downloading Voz" download "$url" "$work"
    step "Installing Voz" install_app "$work"
    step "Opening Voz" open_and_wait
    echo "Voz is running. Finish setup in the panel under the mouth icon in the menu bar."
}

main
