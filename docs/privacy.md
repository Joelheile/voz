# Privacy

What stays on your Mac:

- Audio. voz keeps it in memory and does not write it to disk. If an extension listens for recordings, voz writes each one to a temporary file and deletes it after the extension finishes.
- Transcripts, dictionary words, and stats. They are stored in `~/Library/Application Support/voz`, readable only by your user.
- Speech recognition and cleanup. Both run on your Mac.

What leaves your Mac:

- Anonymous usage events, sent to PostHog (EU). They contain timings, counts, the app and macOS version, the chip, and a random install ID. They do not contain transcript text, dictionary words, or app names. To turn them off, use onboarding or Settings.
- Update checks and downloads, from GitHub through Sparkle.
- Speech model downloads, from Hugging Face.
- Bun, from GitHub, the first time you use an extension. Packages you install, from npm or git.

voz makes no other network requests. Extensions you install can make their own.
