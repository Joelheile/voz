<div align="center">

# Voz

**Talk instead of type, in every app on your Mac.**

Voz is what you'd get if [Wispr Flow](https://wisprflow.ai) and [pi](https://pi.dev) merged: dictation as simple as Wispr Flow, built like pi as a small core you extend.

[Download](https://github.com/Joelheile/voz/releases/latest) · [Extensions](EXTENSIONS.md) · [Privacy](SECURITY.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/images/ready-dark.png">
  <img src=".github/images/ready-light.png" width="380" alt="The Voz menu bar window with recent transcripts">
</picture>

</div>

## Dictate

Tap right Command, speak, tap again. The text lands at your cursor, in whatever app you're using.

You speak about 150 words a minute and type about 40. Voz drops the "um"s, fixes punctuation and spells names the way your dictionary does. It runs offline on your Mac. Change how it cleans up text by editing the prompt in Settings.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/images/insights-dark.png">
    <img src=".github/images/insights-light.png" width="380" alt="Insights: words this week, speaking speed and top apps">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/images/dictionary-dark.png">
    <img src=".github/images/dictionary-light.png" width="380" alt="Dictionary with names Voz spells your way">
  </picture>
</p>

## Extend

The core records, transcribes, cleans up and inserts. Everything else is an extension, so you bend Voz to how you work, not the other way around.

An extension is a TypeScript file in `~/.voz/extensions`:

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCommand("send it", (event, ctx) => ctx.press("return"));
});
```

Say "let's ship it, send it" and Voz types "Let's ship it", then presses Return.

More examples. Handlers go inside `defineExtension((voz) => { ... })`, imports at the top of the file.

Write casually in Slack:

```ts
voz.on("beforeCleanup", (event, ctx) => {
  if (ctx.app.bundleID !== "com.tinyspeck.slackmacgap") return;
  return { prompt: event.prompt + "\n\nWrite casually. Use lowercase." };
});
```

Expand snippets. Say "my email" and Voz types the address:

```ts
const snippets: Record<string, string> = {
  "my email": "me@example.com",
  "my calendar": "https://cal.com/me",
};

voz.on("beforeInsert", (event) => {
  const snippet = snippets[event.text.toLowerCase().replace(/[.!?]$/, "")];
  if (snippet) return { text: snippet };
});
```

Save notes. Say "note, call the bank tomorrow" and Voz adds it to a file instead of typing it:

```ts
import { appendFileSync } from "node:fs";
import { join } from "node:path";

voz.on("beforeInsert", (event, ctx) => {
  const note = event.text.match(/^note[,:]?\s+(.+)/i)?.[1];
  if (!note) return;
  appendFileSync(join(voz.paths.data, "notes.md"), `- ${note}\n`);
  ctx.notify("Saved to notes");
  return { handled: true };
});
```

Send each dictation to an API. The URL comes from `~/.voz/settings.json`:

```ts
voz.on("afterInsert", async (event, ctx) => {
  await fetch(String(voz.config.webhook), {
    method: "POST",
    body: JSON.stringify({ text: event.text, app: ctx.app.name }),
  });
});
```

Full API in [EXTENSIONS.md](EXTENSIONS.md). To have a coding agent write an extension, open it in `~/.voz`. Voz keeps a guide for agents there in `AGENTS.md`.

Publish to npm with the `voz-package` keyword and your extension shows up on Voz's Extensions page, ranked by downloads. People install it from there or with `voz install npm:<name>`.

Extensions run with your permissions, so install only ones you trust.

## Install

Paste this in Terminal. You need macOS 26 and Apple Silicon.

```
curl -fsSL https://raw.githubusercontent.com/Joelheile/voz/main/install.sh | bash
```

It downloads the latest release, puts Voz in `/Applications` and opens it. Voz then walks you through Microphone, Accessibility and Input Monitoring access. Run the same command to reinstall. Voz updates itself after that.

## Privacy

Your audio and text stay on your Mac. Voz sends its version number on install and update, and you can turn that off. Usage analytics stay off unless you opt in. Details in [SECURITY.md](SECURITY.md).

## Contribute

Pull requests are for what every user needs: speed, reliability, fixes, languages and extension points. Everything else ships as a package.

```
scripts/test.sh
scripts/make-app.sh
```

## License

[MIT](LICENSE)
