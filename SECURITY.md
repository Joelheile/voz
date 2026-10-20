# Security and privacy

## Report a vulnerability

Open a private security advisory at https://github.com/Joelheile/voz/security/advisories/new. Do not open a public issue.

Include the Voz version, macOS version and steps to reproduce. You get a first response within 7 days.

## Supported versions

Only the latest stable release and the latest beta get fixes.

## What stays on your Mac

- Audio stays in memory and Voz never writes it to disk on its own. If an extension listens for recordings, Voz writes each one to a temporary file and deletes it once the extension finishes
- Transcripts, dictionary words and stats live in `~/Library/Application Support/voz`. The directory has mode 0700 and the database 0600
- Speech recognition and cleanup run on your Mac
- Logs mark user text and error details as private
- Text that Voz inserts without keeping a copy is marked transient and concealed on the pasteboard, so clipboard managers skip it. Voz then restores your clipboard
- Edit learning never reads secure text fields

## What leaves your Mac

- A version ping to PostHog (EU), once on install and once after each update. It holds the version number and whether it's an install or an update, with a new random ID each time. Turn it off in Settings
- Anonymous usage events to PostHog (EU), only if you opt in. They hold timings, counts, the app and macOS version, the chip and a random install ID. They never hold transcript text, dictionary words or app names
- Update checks and downloads from GitHub through Sparkle
- Speech model downloads from Hugging Face
- The extension list from the npm registry, when you open Extensions
- Bun from GitHub the first time you use an extension, and packages you install from npm or git

Voz makes no other network requests. Extensions you install can make their own.

## Extensions

- Installs never run package scripts and pin exact npm versions
- Voz rejects package names, git paths and refs that could pass a command-line flag or leave the packages directory
- Voz checks the Bun download against a pinned SHA-256 checksum
- The Extensions page asks you to confirm each install and links to the package source

## Updates

Updates are signed with an EdDSA key. Sparkle checks the signature before it installs an update.

## Entitlements

Voz requests microphone access and `com.apple.security.cs.disable-library-validation`. The second one lets Voz load `Sparkle.framework`, because the app is signed with a self-signed identity that has no team ID. It goes away once Voz is notarized.
