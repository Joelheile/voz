<div align="center">

# voz

**Talk instead of type, in every app on your Mac.**

voz is what you'd get if [Wispr Flow](https://wisprflow.ai) and [pi](https://pi.dev) merged: dictation as simple as Wispr Flow, built like pi as a small core you extend.

[Download](https://github.com/Joelheile/voz/releases/latest) · [Extensions](EXTENSIONS.md) · [Privacy](SECURITY.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/images/ready-dark.png">
  <img src=".github/images/ready-light.png" width="380" alt="The voz menu bar window with recent transcripts">
</picture>

</div>

## Dictate

Tap right Command, speak, tap again. The text lands at your cursor, in whatever app you're using.

You speak about 150 words a minute and type about 40. voz drops the "um"s, fixes punctuation and spells names the way your dictionary does. It runs offline on your Mac. Change how it cleans up text by editing the prompt in Settings.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/images/insights-dark.png">
    <img src=".github/images/insights-light.png" width="380" alt="Insights: words this week, speaking speed and top apps">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/images/dictionary-dark.png">
    <img src=".github/images/dictionary-light.png" width="380" alt="Dictionary with names voz spells your way">
  </picture>
</p>

## Extend

The core records, transcribes, cleans up and inserts. Everything else is an extension, so you bend voz to how you work, not the other way around.

An extension is a TypeScript file in `~/.voz/extensions`:

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCommand("send it", (event, ctx) => ctx.press("return"));
});
```

Say "let's ship it, send it" and voz types "Let's ship it", then presses Return.

Use a different cleanup prompt per app, expand snippets, save notes, call an API. To have a coding agent write one, open it in `~/.voz`. voz keeps a guide for agents there in `AGENTS.md`.

Publish to npm with the `voz-package` keyword and your extension shows up on voz's Extensions page, ranked by downloads. People install it from there or with `voz install npm:<name>`.

Extensions run with your permissions, so install only ones you trust.

## Install

Paste this in Terminal. You need macOS 26 and Apple Silicon.

```
curl -fsSL https://raw.githubusercontent.com/Joelheile/voz/main/install.sh | bash
```

It downloads the latest release, puts voz in `/Applications` and opens it. voz then walks you through Microphone, Accessibility and Input Monitoring access. Run the same command to reinstall. voz updates itself after that.

## Privacy

Your audio and text stay on your Mac. voz sends its version number on install and update, and you can turn that off. Usage analytics stay off unless you opt in. Details in [SECURITY.md](SECURITY.md).

## Contribute

Pull requests are for what every user needs: speed, reliability, fixes, languages and extension points. Everything else ships as a package.

```
scripts/test.sh
scripts/make-app.sh
```

## License

[MIT](LICENSE)
