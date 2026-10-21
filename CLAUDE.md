# Voz

## Problem

- Dictation apps charge monthly to talk
- They grow a hundred settings, and each one slows and complicates the core
- Want a change? Open an issue or PR and wait for the maintainer, often forever

## Vision

Voz is the fastest, most reliable, simplest and most extensible voice transcriber. It is pi.dev for local-first dictation: a tiny core that everyone extends with packages.

Voz answers each problem: free and open source, a tiny core with no settings maze, and no PR needed because your coding agent writes the extension from `~/.voz/AGENTS.md`. It is for people who want their tools their way.

- Speed, reliability and simplicity beat features. Voz is always on. Nothing may slow down or break dictation
- The core records, transcribes, cleans up, inserts and saves history. Everything else is an extension
- Primitives, not features. Add an extension point before you add a feature

## Extensions

- Only extensions for now. No dictionary packs, no theme packages, no other resource types
- Extensions are TypeScript, run by Bun (downloaded on demand) in a child process, configured in `~/.voz`. API in `EXTENSIONS.md`
- Extensions have full access: UI, voice and paths. No sandbox
- UI access is through native primitives that Swift renders: toast/HUD, panel rows and actions, settings forms from a JSON schema. No webviews, no React renderer
- No extensions installed: no Bun download, no child process, no cost
- Contributions: PRs to core only for what every user needs on every dictation (speed, reliability, fixes, languages, extension points). Features some users want ship as npm packages with the `voz-package` keyword. No review registry
- A crashed or slow extension never blocks dictation. Steps that change output have a timeout and fall back to the original. Observe-only events never wait

## Build

- Swift package, no Xcode project. Command Line Tools only (no `metal`, no `actool`). macOS 26, Apple Silicon
- `scripts/test.sh` runs tests. `scripts/make-app.sh [--debug] [version] [build]` builds and signs `build/voz.app`
- `voz --render-design <dir>` renders every popover page in light and dark to PNG. README screenshots live in `.github/images`
- Signing identity "voz Dev" (self-signed) must never change: macOS keeps mic and Accessibility grants only while it stays the same
- Push to `main` publishes a beta, tag `vX.Y.Z` publishes stable. Sparkle reads `appcast.xml` in the repo root
- `disable-library-validation` stays until Voz is notarized with a Developer ID

## Design

- Dark and light mode, following the system. No other themes. The notch indicator stays dark, like the hardware notch
- Quiet look: warm canvas, white panel, Geist Pixel Square for titles, Geist for everything else. SF Pro only inside SF Symbols
- Indigo accent (#5163F9 light, #6475FA dark) only for the status dot, Insights bars and the notch level bars. Controls use the system accent color
- Everything lives in the menu bar panel, no main window
- Copy: short, active, sentence case. Inline lists join with commas, no middle dots
- The name is Voz. Lowercase `voz` only for the CLI command, module name, paths and bundle files

## Docs

- `docs/` is gitignored and holds local notes and research only
- Public docs: `README.md`, `EXTENSIONS.md`, `SECURITY.md`

## Telemetry

- Every install sends an anonymous version ping on install and on each update, like pi. Users can turn it off
- PostHog usage analytics only when the user opts in during onboarding
- Never send transcript text, dictionary words or app names
