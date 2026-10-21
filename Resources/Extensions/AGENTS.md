# Writing Voz extensions

Voz is a dictation app for the Mac. You are in `~/.voz`. An extension is one TypeScript file in `~/.voz/extensions` that changes what Voz does with a dictation. Voz runs it with Bun and reloads it when the file is saved.

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
2. `beforeInsert`: before Voz types the text. Return `{ text }` to change it, `{ handled: true }` to type nothing, or nothing to keep it
3. `afterInsert`: after Voz typed the text. Voz does not wait for it
4. `recording`: a 16 kHz mono WAV of the dictation. Voz does not wait for it
5. `registerCommand(phrase, handler)`: runs when a dictation ends with `phrase`. Voz types the words before it first
6. `registerSpeechModel({ id, name, transcribe })`: a speech model. `transcribe` gets a WAV `path` and returns `{ text }`
7. `registerCleanupModel({ id, name, clean })`: replaces the on-device cleanup model. `clean` gets `text` and `prompt` and returns `{ text }`
8. `registerCleanupStep({ id, name, run })`: a cleanup step. `run` gets `text` and returns `{ text }`
9. `registerAction({ id, name, hotkey, run })`: a button in the Voz panel, with an optional global hotkey such as `"ctrl+opt+j"`. `run` gets `ctx`
10. `settings(schema)`: a settings form in the Extensions page. Returns the typed values with defaults filled in

Registering a model or step only makes it available. The user picks it in Settings, or you set `speechModel`, `cleanupModel` or `cleanupSteps` in `~/.voz/settings.json` to `<extension name>/<id>`. `cleanupSteps` is the full ordered list, by default `["fillers", "punctuation", "dictionary", "model"]`

## Rules

- `beforeCleanup` and `beforeInsert` share a 300 ms budget with every other extension. No network calls or model calls there. Do slow work in a command or in `afterInsert`
- A cleanup step has 300 ms, cut short if the cleanup budget runs out. A speech model has 2 seconds per part. A cleanup model has what is left of 1.5 seconds after the user stops talking. Prefer local, fast models. On failure or timeout Voz falls back to its built-in models
- The default export has 3 seconds to finish. Register handlers there and do nothing slow
- Give feedback with `ctx.notify("Sent to Linear")`. It shows a short message under the menu bar
- Anything the user may want to change is a setting. Declare it with `voz.settings({ key: { type, title, default } })`. `type` is `string`, `number` or `boolean`. A string can have `options` for a picker, `secret: true` for a token, or `required: true` when the extension can't work without it. Never ask the user to edit `settings.json`
- Write files to `voz.paths.data`, never next to the extension, or Voz reloads it on every write
- A package declares the API it targets with `"voz": { "apiVersion": 1 }` in `package.json`
- The user turns extensions on or off in the Extensions page. Don't build your own on/off switch
- Log with `voz.log` or `console.log`
- Use Bun and Node APIs (`fetch`, `Bun.spawn`, `node:fs`). Files in `~/.voz/extensions` can't import npm packages. If you need one, make a folder with a `package.json` and an `index.ts`, then run `voz install ./that-folder`
- Never read or send transcripts anywhere the user didn't ask for

## Test

Voz loads a file in `~/.voz/extensions` as soon as you save it. Dictate in any app to try it.

To start an extension the user wants to share, run `voz new voz-<name>` in the folder where they keep code, then `voz dev voz-<name>`. Voz loads it, reloads it on save, prints its logs and writes the types to `voz.d.ts` in that folder.

## Share

Run `npm publish` in a folder made with `voz new`. Its `package.json` already has `"keywords": ["voz-package"]`, so it shows up in the Extensions page. Others install it with `voz install <name>`.
