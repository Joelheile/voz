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

- `App`: entry point, app delegate, settings, login item, updates, permissions, headless CLI.
- `Dictation`: one dictation from hotkey to inserted text. `DictationPipeline` orders the steps.
- `Audio`, `Transcription`, `Cleanup`, `Text`: capture, speech to text, on-device model cleanup, deterministic text rules.
- `Extensions`: Bun host process, JSON protocol, npm packages, `~/.voz`. `Resources/Extensions` holds the TypeScript side.
- `Control`: the `voz` CLI and `voz mcp`. One command table in `ControlCommands` serves both through a Unix socket in the running app. Extension tools and actions join as `<extension>/<id>`, typed as words: `voz jira issues`. See CLI and MCP below.
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

## CLI and MCP

Voz is a dictation app that people and agents drive the same way. Everything you can do in the menu is a `voz` command, and `voz mcp` offers the same commands to AI apps. Extensions add commands through `voz.registerTool`, so the CLI grows with them instead of through a second interface. An agent should be able to dictate, search history, set up an extension or debug one without help from you.

- Keep one command table. A command is a `ControlCommand` in `ControlCommands` (served by the app) or `LocalCommands` (run in the terminal), or a tool an extension registers. Help, flags, JSON, search and MCP all come from it. Don't add a second parser or a special case in `main.swift`.
- Names are paths you also type as words: `vocabulary/add` is `voz vocabulary add`. Extension commands are `<extension>/<id>`, and the `voz-` prefix is optional.
- Each command declares typed input and returns a `ControlOutput`: a JSON value for `--json` and agents, and text for people. Agents get JSON without the flag.
- Exit codes: 0 ok, 1 failed, 2 usage, 3 Voz not running, 4 no speech. Each error says what to run next.
- Repeating a command is safe. When nothing changes, report `changed: false` and exit 0.
- Mark commands that only read as `readOnly`, so agents can call them without asking.
- Only `voz start` and `voz mcp` open the app. Other app commands fail fast with exit 3.
- Put commands that work without the app in `LocalCommands`. Mark commands that stream, wait for Ctrl-C or install code `terminalOnly`, so MCP doesn't offer them.
- Never remove or rename a command or flag. Scripts and agents depend on them, so add new ones instead. Bump `ControlProtocol.version` only when the request or reply shape changes.
- Extension tools have 60 seconds. Commands follow the privacy rules: no transcript text in logs unless the user turns it on.
- Test commands through `ControlCenter.handle` in `ControlTests` and `ControlCommandsTests`.

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
- Release notes and `CHANGELOG.md` list only `Changelog:` commit trailers. Add one per change users notice, such as `Changelog: See the time left while a speech model downloads`. Leave it off refactors, tests, dependency bumps and fixes to unreleased features.
- Write each trailer as one line under 15 words: what the user can now do, or the symptom that went away. Use "you", plain words and the place to find it. No PR numbers, file names, hype, emojis or exclamation marks. One warm or specific detail beats a joke.
- CI adds new trailers to the top of the "In beta" section of `CHANGELOG.md` and renames that section to the version at a stable tag. The menu and README show the file. If your change makes an "In beta" entry wrong or redundant, edit or remove that entry in the same pull request. Your edits stick.
- `install.sh` and `appcast.xml` stay at the repo root. The landing page and shipped apps link to them.
- Keep `disable-library-validation` until every release is notarized with a Developer ID.

Local research and plans go in the gitignored `docs/`. Public docs are `README.md` and `EXTENSIONS.md`.
