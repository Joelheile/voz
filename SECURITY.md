# Security

## Report a vulnerability

Open a private security advisory at https://github.com/Joelheile/voz/security/advisories/new. Do not open a public issue.

Include the voz version, macOS version and steps to reproduce. You receive a first response within 7 days.

## Supported versions

Only the latest stable release and the latest beta receive fixes.

## Data handling

- Audio stays in memory. voz does not write it to disk. voz releases it after each dictation, except the last recording that "Retry last" needs.
- Transcripts, dictionary words, and stats are stored in `~/Library/Application Support/voz`. The directory has mode 0700 and the database has mode 0600.
- Log messages that can contain user text or error details are marked private.
- When voz inserts text without keeping a copy, it marks the text as transient and concealed on the pasteboard, so clipboard managers skip it. voz then restores your previous clipboard.
- Edit learning does not read secure text fields.
- Analytics do not include transcript text, dictionary words, or app names.

## Network

voz connects only to PostHog (EU) for analytics, GitHub for Sparkle updates, and Hugging Face for model downloads.

## Updates

Updates are signed with an EdDSA key. Sparkle verifies the signature before it installs an update.

## Entitlements

voz requests microphone access and `com.apple.security.cs.disable-library-validation`. `docs/releasing.md` explains why voz needs the second entitlement.
