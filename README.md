# voz

voz is a dictation app for the Mac menu bar. Press a hotkey, speak, and voz types the cleaned text into the app you are using.

Transcription and cleanup run on your Mac. voz needs macOS 26 and Apple Silicon.

## Install

Download the latest zip from the [releases page](https://github.com/Joelheile/voz/releases), unzip it and move `voz.app` to `/Applications`. Open it once. voz then starts at login and restarts if it crashes. Choose Quit from the menu bar icon to stop it until the next login or launch.

To install from source:

```
scripts/install.sh
```

This builds a release, quits the running voz, replaces `/Applications/voz.app` and opens it.

## Permissions

| Permission | Why |
| --- | --- |
| Microphone | Record your voice while you dictate. |
| Accessibility | Paste text into the active app and read edits to suggest vocabulary. |
| Input Monitoring | Detect the hotkey. |

voz never reads secure text fields such as password inputs.

## Use

- Default hotkey: right Command. Tap to start, tap again to stop. Hold to talk is a setting.
- Pressing the hotkey while voz transcribes does nothing and shakes the indicator.
- Settings cover the hotkey, language, cleanup, output, vocabulary and updates.
- Recordings under 0.3 seconds or without speech are discarded.

## Build from source

You need macOS 26, the Swift 6.2 toolchain and a code signing identity.

```
scripts/test.sh
scripts/make-app.sh
```

`scripts/make-app.sh` builds `build/voz.app`. Set `SIGNING_IDENTITY` to use your own identity. A stable identity keeps macOS permissions across rebuilds.

`scripts/run.sh` runs a debug build from `build/voz.app` and stops the installed launch agent. Use it only for development. Run `scripts/install.sh` to return to the normal setup.

Headless modes for testing: `voz --transcribe <audio file>`, `voz --clean <text>`, `voz --simulate-dictation <audio file>`.

## Privacy

What stays on your Mac:

- Audio. voz keeps it in memory and never writes it to disk.
- Transcripts, history, vocabulary and stats. They live in `~/Library/Application Support/voz`, readable only by your user.
- Speech recognition and cleanup. Both run on device.

What leaves your Mac:

- Anonymous usage events to PostHog (EU). They carry timings, counts, app and macOS version, chip and a random install ID. They never carry transcript text, vocabulary or app names. You can turn this off in onboarding or Settings.
- Update checks and downloads from GitHub through Sparkle.
- One-time speech model downloads from Hugging Face.

voz makes no other network requests.

## License

See the repository for license terms.
