# Writing voz extensions

voz is a dictation app for the Mac. You are in `~/.voz`. An extension is one TypeScript file in `~/.voz/extensions` that changes what voz does with a dictation. voz runs it with Bun and reloads it when the file is saved.

## Template

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCommand("send it", (event, ctx) => ctx.press("return"));
});
```

The full types are in `~/.voz/node_modules/voz/index.d.ts`. Read them before you write code.

## What runs when

1. `beforeCleanup`: before the on-device model cleans up the text. Return `{ prompt }` to change the cleanup prompt, for example per app with `ctx.app.bundleID`. Append to `event.prompt` instead of replacing it, unless the user asks for a new prompt
2. `beforeInsert`: before voz types the text. Return `{ text }` to change it, `{ handled: true }` to type nothing, or nothing to keep it
3. `afterInsert`: after voz typed the text. voz does not wait for it
4. `recording`: a 16 kHz mono WAV of the dictation. voz does not wait for it
5. `registerCommand(phrase, handler)`: runs when a dictation ends with `phrase`. voz types the words before it first

## Rules

- `beforeCleanup` and `beforeInsert` share a 300 ms budget with every other extension. No network calls or model calls there. Do slow work in a command or in `afterInsert`
- Give feedback with `ctx.notify("Sent to Linear")`. It shows a short message under the menu bar
- Read settings from `voz.config`. The user sets them in `~/.voz/settings.json` under `config.<extension name>`
- Write files to `voz.paths.data`, never next to the extension, or voz reloads it on every write
- Log with `voz.log` or `console.log`
- Use Bun and Node APIs (`fetch`, `Bun.spawn`, `node:fs`). Files in `~/.voz/extensions` can't import npm packages. If you need one, make a folder with a `package.json` and an `index.ts`, then run `voz install ./that-folder`
- Never read or send transcripts anywhere the user didn't ask for

## Test

voz loads a file in `~/.voz/extensions` as soon as you save it. Dictate in any app to try it.

To work on a folder elsewhere, give it an `index.ts` and run `voz dev ./my-extension`. voz loads it, reloads it on save and prints its logs.

## Share

Publish the folder to npm with `"keywords": ["voz-package"]` in `package.json`. It then shows up on the Extensions page in voz.
