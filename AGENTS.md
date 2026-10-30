# Voz

Local macOS dictation in Swift. The app records, transcribes, cleans, inserts and saves history. Optional features ship as TypeScript extensions run by Bun.

## Repo layout

Capitalized folders follow SwiftPM and app bundle conventions. Lowercase folders hold tooling and samples.

- `Sources/Voz`: the app. See the code map below.
- `Tests/VozTests`: unit tests. `Tests/Fixtures` holds cases for `voz --eval`.
- `Resources`: files `scripts/make-app.sh` copies into `voz.app`: Info.plist, icons, sounds, fonts and the extension host in `Resources/Extensions`.
- `scripts`: build, test, signing and release scripts used locally and by `.github/workflows`.
- `examples`: published sample extensions, linked from `EXTENSIONS.md`.
- `install.sh`, `appcast.xml`: installer and update feed. See release hazards.

## Code map

One SwiftPM executable target, `Sources/Voz`, grouped by feature. `Tests/VozTests` imports it with `@testable import Voz`.

- `App`: entry point, app delegate, settings, launch agent, updates, permissions, headless CLI.
- `Dictation`: one dictation from hotkey to inserted text. `DictationPipeline` orders the steps.
- `Audio`, `Transcription`, `Cleanup`, `Text`: capture, speech to text, on-device model cleanup, deterministic text rules.
- `Extensions`: Bun host process, JSON protocol, npm packages, `~/.voz`. `Resources/Extensions` holds the TypeScript side.
- `History`, `Vocabulary`, `Analytics`, `Hotkey`, `Indicator`, `Menu`, `Design`: what the names say. `Design/Components.swift` holds the shared controls and panel views.
- `Support`: small concurrency and `Duration` helpers shared across features.

## Constraints

- Builds must work with the Command Line Tools on Apple Silicon and macOS 26. Xcode-only tools are not available locally.
- Extension failures must not block dictation. Text-changing hooks have deadlines. Observation hooks do not delay delivery.
- Extension API only grows: since `apiVersion` 4, never remove or change a member. When you add one, bump `apiVersion` in `host.ts` and `voz.d.ts` (`voz new` copies it into the template), and add a row to the Versions table in `EXTENSIONS.md`. Older surfaces live in `versionChanges` in `host.ts`, each with a test that loads a package declaring that version. An API with "no users" can still have published ones: search npm for the `voz-package` keyword first.
- Without installed extensions, Bun stays absent. Extensions run unsandboxed in a separate process. Read `EXTENSIONS.md` before you change their interface.
- Keep transcript text, vocabulary and app names out of telemetry. Usage analytics require opt-in. Read the README privacy section before you change privacy behavior.
- Keep the native menu bar UI and its theme. Add optional behavior through extension primitives.
- Test files cannot import `Testing` and `Foundation` together under the Command Line Tools. Put Foundation helpers in `Tests/VozTests/TestSupport.swift`.

## Design

- Every element earns its place. Signal only states that need attention, such as recording. Keep nav icons visible.
- Use Lucide icons through `Icon`, not SF Symbols. Use stroke 1.25 in the popover and 2 to 2.25 in the indicator.
- Take colors, radii and motion from `Theme`. Reuse `PanelGroup`, `PanelRow`, `IconButton` and the `.pill` and `.pressable` styles before you add a component.
- Motion gives feedback or shows a state change, never decoration. Keep it under 300ms and use ease-out or a spring with bounce 0.3 or less. Don't move anything on hover; change only color or background. Under Reduce Motion, keep opacity changes and drop movement.
- Check UI changes with `.build/debug/Voz --render-design <new dir>` in light and dark.

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
