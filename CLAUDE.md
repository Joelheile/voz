# Voz

Local macOS dictation. The core records, transcribes, cleans, inserts and saves history; optional features belong in extensions.

## Constraints

- Preserve Command Line Tools builds on Apple Silicon and macOS 26; Xcode-only tools are unavailable locally.
- Extension failures must not block dictation. Text-changing hooks have deadlines; observation hooks do not delay delivery.
- Without installed extensions, Bun stays absent. Extensions run unsandboxed in a separate process. Read `EXTENSIONS.md` before changing their interface.
- Keep transcript text, vocabulary and app names out of telemetry. Usage analytics require opt-in. Read the README privacy section before changing privacy behavior.
- Keep the native menu bar UI and its existing theme; add optional behavior through extension primitives.

## Verify

- `scripts/test.sh`: public-interface tests, including Bun integration when Bun is installed.
- `scripts/test.sh release`: the optimized configuration used by CI and packaging.
- `scripts/make-app.sh [--debug] [version] [build]`: build and verify the signed app.

## Release hazards

- Preserve the signing identity, Sparkle key, bundle identifier and appcast URL; changes can break permissions or updates.
- Push to `main` publishes beta; tag `vX.Y.Z` publishes stable. See `README.md` for release recovery. Keep build numbers increasing.
- Keep `disable-library-validation` until Developer ID notarization is required for every release.

Local research and plans belong in gitignored `docs/`. Public docs are `README.md` and `EXTENSIONS.md`.
