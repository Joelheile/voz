#!/bin/bash
# Layer 1: speech to final text from audio files, with the real models. No app, no microphone, nothing on screen.
set -uo pipefail
cd "$(dirname "$0")/.."

VOZ=.build/debug/Voz
MAX_RELEASE_TO_TEXT_MS=${MAX_RELEASE_TO_TEXT_MS:-2000}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swift build -q || exit 1

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

# Lowercase words only, so the check doesn't fail on punctuation
words() { tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:] \n' | tr -s ' '; }

check() {
    local voice=$1 expected=$2
    local name audio output final latency
    name=$(echo "$voice $expected" | shasum | cut -c1-8)
    audio="$WORK/$name.wav"
    say -v "$voice" -o "$audio" --data-format=LEI16@16000 "$expected" || { fail "say could not use voice $voice"; return; }
    output=$("$VOZ" --simulate-dictation "$audio" --speed 20 2>&1) || { fail "\"$expected\": $output"; return; }
    final=$(sed -n 's/^final: //p' <<<"$output")
    latency=$(sed -n 's/.*release_to_text_ms=\([0-9]*\).*/\1/p' <<<"$output")
    if [[ "$(words <<<"$final")" != "$(words <<<"$expected")" ]]; then
        fail "\"$expected\" became \"$final\""
    elif (( latency > MAX_RELEASE_TO_TEXT_MS )); then
        fail "\"$expected\" took ${latency} ms, budget ${MAX_RELEASE_TO_TEXT_MS} ms"
    else
        echo "ok   ${latency} ms  $voice"
    fi
}

check Samantha "Please send the quarterly report to Anna by Friday."
check Samantha "The meeting starts early tomorrow morning."
check Anna "Ich schicke dir den Bericht morgen früh."

if (( failures > 0 )); then
    echo "FAILED: $failures"
    exit 1
fi
echo "PASSED: audio"
