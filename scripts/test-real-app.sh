#!/bin/bash
# Layer 2: the real app, the real microphone path and the real CLI, next to your installed Voz.
# BlackHole 2ch is a silent virtual microphone, and `say` speaks into it, so you hear nothing and nothing types into your apps.
# Grant the microphone once on the first run. The notch shows a recording pill during the run.
set -uo pipefail
cd "$(dirname "$0")/.."

APP=build/voz-test.app
VOZ=$APP/Contents/MacOS/voz
BUNDLE_ID=com.joelheile.voz.test
DEVICE="BlackHole 2ch"
DEVICE_UID=BlackHole2ch_UID

if ! say -a '?' | grep -q "$DEVICE"; then
    echo "FAIL install BlackHole: brew install blackhole-2ch"
    exit 2
fi
export SIGNING_IDENTITY=${SIGNING_IDENTITY:-$(security find-identity -p codesigning -v | sed -n 's/.*) \([0-9A-F]\{40\}\) .*G2CSKBA739.*/\1/p' | head -1)}
[[ -n "$SIGNING_IDENTITY" ]] || SIGNING_IDENTITY=-
scripts/make-app.sh --test >/dev/null || { echo "FAIL build"; exit 1; }

stop_app() { pkill -f "$PWD/$VOZ" 2>/dev/null; }
trap stop_app EXIT
stop_app
installed_before=$(pgrep -f '^/Applications/voz.app/Contents/MacOS/voz$' | head -1)

defaults write "$BUNDLE_ID" onboardingCompleted -bool true
open -g -j "$APP"
for _ in $(seq 40); do "$VOZ" status --json >/dev/null 2>&1 && break; sleep 0.25; done

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
pass() { echo "ok   $1"; }
words() { tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:] \n' | tr -s ' '; }
field() { python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }

for setting in "microphone $DEVICE_UID" "insertIntoApp off" "copyToClipboard off" "soundCues off" "muteWhileRecording off" "livePreview off" "cleanup off"; do
    # shellcheck disable=SC2086
    "$VOZ" settings $setting >/dev/null || fail "could not set $setting"
done

microphone_granted() {
    local status
    status=$("$VOZ" status --json) || { echo "FAIL the test app did not answer"; exit 1; }
    [[ "$(field microphone <<<"$status")" == True ]]
}
if ! microphone_granted; then
    echo "Waiting up to ${MICROPHONE_WAIT:=90} seconds: allow Voz Test to use the microphone."
    for _ in $(seq "$MICROPHONE_WAIT"); do microphone_granted && break; sleep 1; done
fi
if ! microphone_granted; then
    echo "FAIL microphone not granted. Turn on Voz Test in System Settings, Privacy & Security, Microphone, then run this again."
    exit 2
fi
pass "test app is running with the microphone"

dictate() {
    local expected=$1 output
    "$VOZ" dictation start >/dev/null || { fail "start: \"$expected\""; return; }
    sleep 0.3
    say -a "$DEVICE" "$expected"
    sleep 0.5
    output=$("$VOZ" dictation stop --print --json 2>&1)
    local code=$?
    if (( code == 4 )); then fail "no speech for \"$expected\". Set $DEVICE input and output volume to full in Audio MIDI Setup."; return; fi
    if (( code != 0 )); then fail "stop exited $code for \"$expected\": $output"; return; fi
    local text
    text=$(field text <<<"$output")
    if [[ "$(words <<<"$text")" == "$(words <<<"$expected")" ]]; then pass "heard \"$text\""; else fail "said \"$expected\", got \"$text\""; fi
}

dictate "Please send the quarterly report to Anna by Friday."
dictate "The meeting starts early tomorrow morning."

last=$("$VOZ" last --json 2>&1) && [[ "$(field text <<<"$last" | words)" == "$(words <<<"The meeting starts early tomorrow morning.")" ]] \
    && pass "history saved the last dictation" || fail "history: $last"

"$VOZ" dictation start >/dev/null
sleep 1
"$VOZ" dictation stop --print >/dev/null 2>&1
code=$?
if (( code == 4 )); then pass "silence exits 4"; else fail "silence exited $code, expected 4"; fi

[[ -S "$HOME/Library/Application Support/voz-test/control.sock" ]] && pass "test app uses its own data folder" || fail "control socket is not in voz-test"
installed_after=$(pgrep -f '^/Applications/voz.app/Contents/MacOS/voz$' | head -1)
[[ "$installed_before" == "$installed_after" ]] && pass "installed Voz was left alone" || fail "installed Voz changed from pid $installed_before to $installed_after"

if (( failures > 0 )); then
    echo "FAILED: $failures"
    exit 1
fi
echo "PASSED: real app"
