<div align="center">

# Voz

**Free, offline dictation for your Mac. Talk, and clean text appears where you type.**

[Website](https://voz.joels.tech), [Extensions](https://voz.joels.tech/extensions/)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/images/ready-dark.png">
  <img src=".github/images/ready-light.png" width="380" alt="The Voz menu bar panel with recent transcripts">
</picture>

</div>

You talk at 150 words a minute and type at 40. Dictation apps fix that, but they charge every month, pile on settings, and if you want a change you wait for someone else to build it.

Voz is free and open source. It runs on your Mac and works offline. You talk, it types. Everything else is an extension you can write yourself.

## Install

macOS 26 on Apple Silicon:

```
curl -fsSL https://voz.joels.tech/install | bash
```

## Use

Tap right Command, talk, tap again. You say:

> um so tell kaitlyn the uh deck is ready

Voz types this at your cursor, in any app:

> Tell Kaitlyn the deck is ready.

Your recent transcripts live in the menu bar.

## Extensions

An extension is a TypeScript file in `~/.voz/extensions`:

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCommand("send it", (event, ctx) => ctx.press("return"));
});
```

Now "let's ship it, send it" types "Let's ship it" and presses Return.

You don't have to learn the API. Open a coding agent in `~/.voz`, say what you want, and it writes the extension. Publish it to npm with the `voz-package` keyword and anyone can install it from the menu bar. The API is in [EXTENSIONS.md](EXTENSIONS.md).

Extensions run with your permissions, so install ones you trust. A slow or broken extension never blocks dictation.

## Privacy

Audio and transcripts never leave your Mac. Voz sends an anonymous version ping on install and update, which you can turn off. Usage analytics are off unless you opt in, and they never contain what you said.

To mute other apps while you dictate, Voz asks for System Audio Recording access. It silences their sound and never records it.

Found a vulnerability? Open a [private advisory](https://github.com/Joelheile/voz/security/advisories/new), not a public issue.

## Contributing

The core stays small: record, transcribe, clean up, type, save history. Pull requests that make that faster or more reliable, add languages or add extension points are welcome. Everything else ships as an extension, and if the API can't do what you need, open an issue.

You need the Command Line Tools, not Xcode:

```
scripts/test.sh          # run the tests
scripts/make-app.sh      # build and sign build/voz.app
```

Pushes to `main` publish a beta and `vX.Y.Z` tags publish a stable release. Keep the signing identity and Sparkle key unchanged and build numbers increasing. To pull a bad update, remove it from `appcast.xml`, then publish a fix.

## License

[MIT](LICENSE)
