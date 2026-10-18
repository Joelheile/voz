# voz plan

Local-first macOS dictation app. Menu bar only. Research: `docs/research/stack.md`.

## Platform and build

- Native Swift, AppKit plus SwiftUI. `LSUIElement` (no Dock icon). macOS 26 only, Apple Silicon.
- Swift package plus `scripts/make-app.sh` that builds, bundles and signs `voz.app`. No Xcode project. Only Command Line Tools are installed (SDK 26.1, no `metal`, no `actool`).
- Own git repo, public `Joelheile/voz`. Bundle ID `com.joelheile.voz`.
- Local signing: self-signed code signing identity "voz Dev" in the login keychain, so TCC grants survive rebuilds. Notarization added later with an individual Apple Developer account.

## Releases

- Sparkle 2 with EdDSA signatures. Channels: beta and stable. Setting "Receive beta updates".
- GitHub Actions: push to `main` builds beta, tag `v*` builds stable. Artifacts on GitHub Releases, appcast in repo.
- Start at login on by default (`SMAppService.mainApp`).

## Recording

- One hotkey: single key (default right Cmd, keycode 54) or a combination, set with a recorder field.
- Default mode: tap to start, tap to stop. Setting adds hold to talk.
- Mute default output device while recording (setting, on by default). Persist a "muted by voz" marker, restore on next launch after a crash. Read back state after setting it.
- `AVAudioEngine` input tap starts on key down. Prefer built-in mic when default input is Bluetooth. Rebuild engine on configuration change.
- No maximum length. Discard recordings under 0.3 s or below a silence threshold.
- Optional start and stop sounds: two short bundled clicks, off by default.

## Transcription

- FluidAudio. Three speech models, chosen in onboarding and Settings. Only the chosen model downloads:
  - Parakeet Ultra, the default: most accurate, 25 languages, 630 MB.
  - Parakeet English (TDT v2): English only, 500 MB.
  - Apple Speech: built into macOS, no download.
- Apple SpeechAnalyzer used while Parakeet downloads or compiles.
- Last recording kept in memory only for "Retry last", cleared on next recording.

## Cleanup

- Apple Foundation Models, light pass: remove filler words, fix punctuation, apply self-corrections, keep language and wording. Toggle in settings.
- Timeout 1.5 s, then paste raw text.
- Vocabulary: manual list plus suggestions learned from edits after paste (AX read-back), approved by the user. Words feed FluidAudio vocabulary boosting and the cleanup prompt.

## Output

- Copy to clipboard and insert into active app. Both on by default, separate toggles.
- Insert via pasteboard plus synthesized Cmd+V, transient pasteboard types, guarded clipboard restore. AX fallback for Chromium.

## Interface

- Menu bar: last 10 transcripts (click to copy), Retry last, History, Stats, Settings, Quit.
- History window: search, raw and cleaned text, copy.
- Stats (like Wispr Flow): words today, week, total; average WPM; time saved vs typing at 40 WPM; day streak; top apps (local only); filler words removed; 30-day chart.
- Indicator built from scratch, no notch library. Setting: notch shape or floating pill on the screen with the active window. Spring expansion from the notch, live level meter.
- Onboarding, short: Microphone, Accessibility, Input Monitoring, then the speech model, then analytics switch, then a test dictation.

## Storage and privacy

- SwiftData in Application Support. Transcripts only, never audio.
- PostHog EU (`https://eu.i.posthog.com`, project token `phc_pprHknWQHntzTK6vR4vzHK9B6hWNv4nKXbAYpkYcoLXS`). On by default, opt-out in onboarding and settings. Never send transcript text, vocabulary or app IDs.

| Event                            | Properties                                                                                                                                                   |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `app_installed`, `app_launched`  | `launch_ms`                                                                                                                                                  |
| `permission_result`              | `permission`, `granted`                                                                                                                                      |
| `dictation_completed`            | `audio_s`, `word_count`, `stt_ms`, `cleanup_ms`, `insert_ms`, `total_ms`, `model`, `selected_model`, `cleanup_used`, `cleanup_timed_out`, `trigger`, `output` |
| `dictation_failed`               | `stage`, `error_code`                                                                                                                                        |
| `dictation_discarded`            | `reason`                                                                                                                                                     |
| `retry_used`                     |                                                                                                                                                              |
| `model_download`                 | `model`, `seconds`, `success`, `bytes`                                                                                                                       |
| `model_load`                     | `model`, `cold_ms`                                                                                                                                           |
| `vocabulary_suggestion`          | `accepted`                                                                                                                                                   |
| `setting_changed`                | `key`, `value`                                                                                                                                               |
| `history_opened`, `stats_opened` |                                                                                                                                                              |
| `update_installed`               | `from`, `to`, `channel`                                                                                                                                      |

Every event carries app version, macOS version, chip and a random install ID.

## Slices

Each slice works end to end before the next starts.

1. Hotkey, record, mute, Parakeet, copy and paste, menu bar.
2. Onboarding, settings, history.
3. Cleanup, vocabulary.
4. Notch and pill indicator.
5. Stats, PostHog.
6. Sparkle and release workflows.
