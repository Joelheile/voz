# Writing Voz extensions

Voz is a Mac dictation app. You are in `~/.voz`. An extension is a TypeScript file in `~/.voz/extensions` that changes what Voz does with a dictation. Voz runs it with Bun and reloads it on save.

Read the types in `~/.voz/node_modules/voz/index.d.ts` before you write code. The full guide is https://raw.githubusercontent.com/Joelheile/voz/main/EXTENSIONS.md.

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCommand("send it", (event, ctx) => ctx.press("return"));
});
```

## API

- `voz.on("beforeCleanup")`: return `{ prompt }` to change the cleanup prompt, for example per app with `ctx.app.bundleID`. Append to `event.prompt` unless the user asks for a new prompt
- `voz.on("beforeInsert")`: return `{ text }` to change what Voz types, `{ text: "" }` to type nothing, or nothing to keep it
- `voz.on("afterInsert")`: runs after Voz typed the text. Voz doesn't wait for it
- `voz.on("recording")`: gets a 16 kHz mono WAV of the dictation. Voz doesn't wait for it
- `registerCommand(phrase, handler)`: runs when a dictation ends with `phrase`, after Voz types the words before it. With `{ at: "start" }`, it runs when a dictation starts with `phrase`, types nothing and passes the words after it
- `registerSpeechModel({ id, name, transcribe })`: `transcribe` gets a WAV `path` and returns `{ text }`
- `registerCleanupModel({ id, name, clean })`: replaces the on-device cleanup model. `clean` gets `text` and `prompt` and returns `{ text }`
- `registerCleanupStep({ id, name, run })`: `run` gets `text` and returns `{ text }`
- `registerAction({ id, name, hotkey, run })`: a button in the Voz panel, with an optional global hotkey such as `"ctrl+opt+j"`. `run` gets `ctx`
- `voz.settings({ key: { type, title, default } })`: a form in the Extensions page. Returns typed values with defaults filled in. `type` is `string`, `number` or `boolean`. A string can have `options` for a picker, `secret: true` for a token, or `required: true` when the extension can't work without it
- `ctx.generate({ prompt, instructions, schema })`: JSON from Apple's on-device model that fits a JSON schema (`object`, `array`, `string` with `enum`, `number`, `integer`, `boolean`). Pass today's date and valid names in the prompt. It takes 1 to 3 seconds
- `ctx.notify("Sent to Linear")`: a short message under the menu bar. Use it for feedback

A registered model or step only becomes available. The user picks it in Settings, or you set `speechModel`, `cleanupModel` or `cleanupSteps` in `~/.voz/settings.json` to `<extension name>/<id>`. `cleanupSteps` is the full ordered list, by default `["fillers", "punctuation", "dictionary", "model"]`.

## Limits

- `beforeCleanup` and `beforeInsert` share 300 ms with every other extension. Make no network or model calls there. Do slow work in a command or `afterInsert`
- A cleanup step has 300 ms. A speech model has 2 seconds per part. A cleanup model has what is left of 1.5 seconds after the user stops talking. On failure or timeout, Voz uses its built-in models
- The default export has 3 seconds. Register handlers there and do nothing slow

## Rules

- Make every value the user may want to change a setting. Never ask the user to edit `settings.json`
- Don't build an on/off switch. The Extensions page has one
- Write files to `voz.paths.data`. A write next to the extension reloads it
- Use Bun and Node APIs such as `fetch`, `Bun.spawn` and `node:fs`. Files in `~/.voz/extensions` can't import npm packages. For a package, make a folder with `package.json` and `index.ts`, then run `voz install ./that-folder`
- Set `"voz": { "apiVersion": 1 }` in a package's `package.json`, or `2` if it calls `ctx.generate` or uses `{ at: "start" }`
- Log with `console.log`
- Never read or send transcripts anywhere the user didn't ask for

## Test and share

Voz loads a file in `~/.voz/extensions` when you save it. Dictate in any app to try it.

For an extension the user wants to share, run `voz new voz-<name>` in their code folder, then `voz dev voz-<name>`. It reloads on save, prints logs and writes the types to `voz.d.ts`. To publish, run `npm publish` in that folder. The `voz-package` keyword lists it in the Extensions page, and others install it with `voz install <name>`.
