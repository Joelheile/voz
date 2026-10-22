# Voz

Local macOS dictation in Swift. The app records, transcribes, cleans, inserts and saves history. Optional features ship as TypeScript extensions run by Bun.

## Code map

One SwiftPM executable target, `Sources/Voz`, grouped by feature. `Tests/VozTests` imports it with `@testable import Voz`.

- `App`: entry point, app delegate, settings, launch agent, updates, permissions, headless CLI.
- `Dictation`: one dictation from hotkey to inserted text. `DictationPipeline` orders the steps.
- `Audio`, `Transcription`, `Cleanup`, `Text`: capture, speech to text, on-device model cleanup, deterministic text rules.
- `Extensions`: Bun host process, JSON protocol, npm packages, `~/.voz`. `Resources/Extensions` holds the TypeScript side.
- `History`, `Vocabulary`, `Analytics`, `Hotkey`, `Indicator`, `Menu`, `Design`: what the names say.

## Constraints

- Builds must work with the Command Line Tools on Apple Silicon and macOS 26. Xcode-only tools are not available locally.
- Extension failures must not block dictation. Text-changing hooks have deadlines. Observation hooks do not delay delivery.
- Without installed extensions, Bun stays absent. Extensions run unsandboxed in a separate process. Read `EXTENSIONS.md` before you change their interface.
- Keep transcript text, vocabulary and app names out of telemetry. Usage analytics require opt-in. Read the README privacy section before you change privacy behavior.
- Keep the native menu bar UI and its theme. Add optional behavior through extension primitives.
- Test files cannot import `Testing` and `Foundation` together under the Command Line Tools. Put Foundation helpers in `Tests/VozTests/TestSupport.swift`.

## Verify

- `scripts/test.sh`: tests, including Bun integration when Bun is installed.
- `scripts/test.sh release`: the optimized configuration CI uses.
- `scripts/make-app.sh [--debug] [version] [build]`: build and verify the signed app.
- `scripts/run.sh`: build a debug app and launch it.
- `scripts/install-local.sh [--debug] [version] [build]`: build the signed app and replace /Applications/voz.app.

## Release hazards

- Do not change the signing identity, Sparkle key, bundle identifier or appcast URL. Changes break permissions or updates.
- Pushes to `main` publish a beta. Tags `vX.Y.Z` publish a stable release. Both run `.github/workflows/release.yml`. Build numbers must keep increasing.
- Changes reach `main` only through a pull request that passes CI. Agents open the pull request. Only the maintainer merges it.
- Release notes list only `Changelog:` commit trailers. Add one per change users notice, written for them, such as `Changelog: Show the time left while a model downloads`. Leave it off internal changes.
- `install.sh` and `appcast.xml` stay at the repo root. The landing page and shipped apps link to them.
- Keep `disable-library-validation` until every release is notarized with a Developer ID.

Local research and plans go in the gitignored `docs/`. Public docs are `README.md` and `EXTENSIONS.md`.
