# Security

## Report a vulnerability

Open a private security advisory at https://github.com/Joelheile/voz/security/advisories/new. Do not open a public issue.

Include the voz version, macOS version and steps to reproduce. You get a first answer within 7 days.

## Supported versions

Only the latest stable release and the latest beta get fixes.

## Data handling

- Audio stays in memory. voz never writes it to disk. It is released after each dictation, except the last recording that "Retry last" needs.
- Transcripts, vocabulary and stats are stored in `~/Library/Application Support/voz`. The directory is mode 0700 and the database is mode 0600.
- Log messages that can contain user text or error details are marked private.
- voz marks text it pastes without keeping a copy as transient and concealed on the pasteboard, so clipboard managers skip it. It restores your previous clipboard afterwards.
- Edit learning never reads secure text fields.
- Analytics never include transcript text, vocabulary or app names.

## Network

voz connects only to PostHog (EU), GitHub for Sparkle updates, and Hugging Face for model downloads.

## Updates

Updates are signed with an EdDSA key and checked by Sparkle before install.

## Entitlements

voz requests microphone access and `com.apple.security.cs.disable-library-validation`. See `docs/releasing.md` for why the second one exists.
