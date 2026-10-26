<div align="center">

# Voz

**Simple like Wispr Flow. Extensible like pi.**

[Website](https://voz.joels.tech), [Extensions](https://voz.joels.tech/extensions/)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/images/ready-dark.png">
  <img src=".github/images/ready-light.png" width="380" alt="The Voz menu bar panel with recent transcripts">
</picture>

</div>

Tap right Command and talk. Voz types clean text into any app. It is free, open source and works offline.

## Install

macOS 26 on Apple Silicon:

```
curl -fsSL https://voz.joels.tech/install | bash
```

Current builds use a project signing certificate and are not notarized by Apple.

## Why I built Voz

I paid for Wispr Flow until paying a subscription to talk to my own computer started to annoy me. The open source apps I tried felt bloated. Hex came closest. I liked it, but every change I wanted meant a pull request and a long wait.

So I built Voz the way pi works. The core records, transcribes, cleans up and types, and I keep it fast. Anything else is an extension you write for yourself.

## Use

Tap right Command, talk, tap again. You say:

> um so tell kaitlyn the uh deck is ready

Voz types this at your cursor:

> Tell Kaitlyn the deck is ready.

Recent transcripts live in the menu bar. Click one to copy it.

## Extensions

Voz has no settings page for every wish. You write an extension instead: a TypeScript file in `~/.voz/extensions`.

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCommand("send it", (event, ctx) => ctx.press("return"));
});
```

Now "let's ship it, send it" types "Let's ship it" and presses Return.

Ideas:

- Turn rambling into a clear prompt for a coding agent
- Write mail with your own greeting and sign-off
- File a Linear issue from what you said
- Run a script with a voice command

You don't need to learn the API first. Open a coding agent in `~/.voz` and say what you want. It reads the guide Voz keeps there and writes the extension. The full API is in [EXTENSIONS.md](EXTENSIONS.md).

Publish to npm with the `voz-package` keyword and anyone can install it from the menu bar.

Extensions run with your permissions, so only install ones you trust. If one is slow or crashes, dictation keeps working.

## Privacy

Built-in dictation processes audio and transcripts on your Mac. Extensions can send data to external services, so review what you install. Voz sends a version ping on install and update. Usage analytics are off unless you opt in, and they never contain what you said. Crash reports are on by default and have their own setting under Privacy. They send crashes, freezes and fixed error codes with a stack trace, never text, audio or app names.

To mute other apps while you dictate, Voz asks for System Audio Recording access. It silences their sound and does not save their audio.

Found a vulnerability? Open a [private advisory](https://github.com/Joelheile/voz/security/advisories/new), not a public issue.

## Contributing

The core stays small. Pull requests that make it faster or more reliable, add languages or add extension points are welcome. Everything else ships as an extension. If the API can't do what you need, open an issue.

You need the Command Line Tools, not Xcode:

```
scripts/test.sh          # run the tests
scripts/run.sh           # build a debug app and launch it
scripts/make-app.sh      # build and sign build/voz.app
```

The app is one Swift package target, `Sources/Voz`, with a folder per feature. `AGENTS.md` has the code map.

Pushes to `main` publish a beta and `vX.Y.Z` tags publish a stable release. Keep the signing identity and Sparkle key unchanged and build numbers increasing. To pull a bad update, remove it from `appcast.xml`, then publish a fix.

## License

[MIT](LICENSE). Dependencies and downloaded models retain their own licenses. Signed apps include `Contents/Resources/ThirdPartyNotices.txt`, with dependency licenses and [model attributions](Resources/ModelNotices.txt).
