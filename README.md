# voz

voz is a local-first dictation app for the Mac. Press a shortcut, speak, and the text appears at your cursor.

voz is a small core you extend with TypeScript. The core records, transcribes, cleans up, inserts and keeps history, all on your Mac. Extensions do the rest: voice commands, per-app rewrites, snippets, anything that hooks into a recording.

voz has no cloud mode, no account and no sandbox for extensions.

## Install

Download the latest zip from [releases](https://github.com/Joelheile/voz/releases), unzip it and move `voz.app` to `/Applications`. voz needs macOS 26 and Apple Silicon.

voz is not notarized yet. Run this once so macOS opens it:

```
xattr -cr /Applications/voz.app
```

To build from source, run `scripts/install.sh`.

## Use

Tap right Command, speak, tap again. voz inserts the text into the front app. Click the menu bar icon for history, stats, dictionary and settings.

voz asks for three permissions:

- Microphone, to record.
- Accessibility, to insert text.
- Input Monitoring, to detect the shortcut.

## Extensions

Put a `.ts` file in `~/.voz/extensions`:

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCommand("send it", (event, ctx) => ctx.press("return"));

  voz.on("beforeInsert", (event, ctx) => {
    if (ctx.app.bundleID !== "com.tinyspeck.slackmacgap") return;
    return { text: event.text.replace(/\bjira (\d+)/gi, "JIRA-$1") };
  });
});
```

Say "let's ship it, send it" in any app. voz types "Let's ship it" and presses Return.

Or install a package from npm, git or a folder:

```
voz install npm:<name>
voz install git:github.com/<user>/<repo>@v1
voz dev ./my-extension
```

voz reloads extensions when you save. With no extensions, voz does not start Bun and costs nothing. Full API: [docs/extensions.md](docs/extensions.md).

To get the `voz` command, open Extensions in the menu bar and choose Install next to "voz command". It links `/usr/local/bin/voz` to the app.

## Security

Extensions run with your user's permissions. They can read your transcripts, your recordings, your files and the network. Install only packages you trust, and read the source first.

voz limits the damage it can control:

- Installs never run package scripts.
- Installs pin exact versions. Packages change only when you run `voz update`.
- A crashed or slow extension never blocks dictation. voz times it out, inserts the original text and restarts the extension.

## Privacy

- Recording, transcription and cleanup run on your Mac.
- Audio stays in memory. voz writes a recording to disk only when an extension listens for it, and deletes it afterwards.
- voz sends anonymous usage counts to PostHog only if you opt in, and checks GitHub for updates.

Details: [docs/privacy.md](docs/privacy.md).

## Contributing

voz keeps its core small. Where a change goes depends on who needs it:

- **Pull request to voz:** changes every user needs on every dictation. Speed, reliability, bug fixes, languages and new extension points.
- **Extension package:** features only some users want, such as snippets, per-app tone or integrations. Publish it to npm with the `voz-package` keyword. You do not need anyone's approval.

Pull requests that add a feature a package could provide are closed with a pointer to [docs/extensions.md](docs/extensions.md). If a package needs something the extension API lacks, open an issue for the missing extension point.

To build and test:

```
scripts/test.sh
scripts/make-app.sh
```

Release process: [docs/releasing.md](docs/releasing.md). Design: [docs/design.md](docs/design.md).

## License

[MIT](LICENSE)
