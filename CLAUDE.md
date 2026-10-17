# voz

## Vision

voz is the fastest, most reliable, simplest and most extensible voice transcriber. It is pi.dev for local-first dictation: a tiny core that everyone extends with packages.

- Speed, reliability and simplicity beat features. voz is always on. Nothing may slow down or break dictation.
- The core records, transcribes, cleans up, inserts and saves history. Everything else is an extension.
- Primitives, not features. Add an extension point before you add a feature.

## Extensions

- Only extensions for now. No dictionary packs, no theme packages, no other resource types.
- Extensions are TypeScript, run by Bun (downloaded on demand) in a child process, configured in `~/.voz`. See `docs/extensions.md`.
- Extensions have full access: UI, voice and paths. No sandbox.
- UI access is through native primitives that Swift renders: toast/HUD, panel rows and actions, settings forms from a JSON schema. No webviews, no React renderer.
- No extensions installed: no Bun download, no child process, no cost.
- A crashed or slow extension never blocks dictation. Steps that change output have a timeout and fall back to the original. Observe-only events never wait.

## Appearance

Dark mode and light mode, following the system. No other themes.

## Telemetry

- Every install sends an anonymous version ping on install and on each update, like pi. Users can turn it off.
- PostHog usage analytics only when the user opts in during onboarding.
