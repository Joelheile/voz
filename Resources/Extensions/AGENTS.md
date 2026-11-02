# Writing Voz extensions

Voz is a dictation app for the Mac. An extension is TypeScript that changes what Voz does with a dictation, or adds commands agents can run. Voz runs it with Bun and reloads it when you save. It lives in one of two places:

- One file in `~/.voz/extensions`, for this user alone. Voz loads it as soon as you save it
- A package made with `voz new voz-<name>`, to share on npm. Load it with `voz dev <folder>`

Run `voz guide` to print the newest copy of this guide.

## Template

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCommand({ phrase: "send it", run: (event, ctx) => ctx.press("return") });
});
```

The full types are in `~/.voz/node_modules/voz/index.d.ts`, or in `voz.d.ts` in a package folder. Read them before you write code.

## What runs when

1. `beforeCleanup`: before the on-device model cleans up the text. Return `{ prompt }` to change the cleanup prompt, for example per app with `ctx.app.bundleID` or per site with `ctx.app.website` (a hostname such as `github.com`). Append to `event.prompt` instead of replacing it, unless the user asks for a new prompt
2. `beforeInsert`: before Voz types the text. Return `{ text }` to change it, `{ text: "" }` to type nothing, or nothing to keep it
3. `afterInsert`: after Voz typed the text. Voz does not wait for it
4. `afterRecording`: a 16 kHz mono WAV of the dictation. Voz does not wait for it
5. `registerCommand({ phrase, run })`: runs when a dictation ends with `phrase`. Voz types the words before it first. With `at: "start"`, it runs when a dictation starts with `phrase`, types nothing and passes the words after it
6. `registerSpeechModel({ id, name, transcribe })`: a speech model. `transcribe` gets a WAV `path` and returns `{ text }`
7. `registerCleanupModel({ id, name, clean })`: replaces the on-device cleanup model. `clean` gets `text` and `prompt` and returns `{ text }`
8. `registerCleanupStep({ id, name, run })`: a cleanup step. `run` gets `text` and returns `{ text }`
9. `registerAction({ id, name, hotkey, hidden, run })`: a button in the Voz panel, with an optional global hotkey such as `"ctrl+opt+j"`. `run` gets `ctx`. `hidden: true` means it does not apply right now: it leaves the panel and stays in the extension's details. It returns a handle: call `update({ hidden })` when your state changes, such as once setup is done
10. `startActivity({ title, since, stop, open })`: shows that something keeps running, such as a recording, in the menu bar and the Voz panel, with a Stop button when you pass `stop`. With `open`, the notch shows it, and clicking the notch runs `open` with `ctx`. Returns `{ end(), transcribeLive(options) }`
11. `addHistory({ text, seconds, file })`: adds an entry, such as a meeting transcript, to the Voz history, where the user can search and copy it. `file` is the path of a file you saved with the same text
12. `settings(schema)`: a settings form in the Extensions page. Returns the typed values with defaults filled in
13. `registerTool({ id, description, input, positional, readOnly, run })`: a command agents and the terminal run as `voz <extension> <id> --flag value`, and AI apps call over MCP. `input` is an object schema like `ctx.generate` takes. `positional` lists inputs typed without a flag. Group tools with `/` in the id, such as `issues/create`. `run(input, ctx)` returns JSON. Set `readOnly: true` when it changes nothing

Registering a model or step only makes it available. The user picks it in Settings, or you set `speechModel`, `cleanupModel` or `cleanupSteps` in `~/.voz/settings.json` to `<extension name>/<id>`. `cleanupSteps` is the full ordered list, by default `["fillers", "punctuation", "dictionary", "model"]`

## Tools for agents

A tool is how a coding agent or AI app uses your extension. Design it for a reader who sees only the name, the description and the schema:

- Name tools with nouns and verbs a person would type: `issues`, `issues/create`. Group related tools under one noun
- Write the description as when to use it: "List my open Jira issues, newest first"
- Give every input a `description` with an example value. Put the one input people always pass in `positional`
- Return small JSON: the fields a caller needs, not the whole API response. Return a list of objects for many items
- Throw an `Error` with a message that says what to do next, such as "Set your Jira token with voz config voz-jira token -"
- Set `readOnly: true` when the tool changes nothing. Return in seconds
- Try it the way an agent will: `voz <name> <id> --help`, then `voz <name> <id> --json`

## Rules

- `beforeCleanup` and `beforeInsert` share a 300 ms budget with every other extension. Their `ctx` has only `app`. No network calls or model calls there. Do slow work in a command or in `afterInsert`
- A cleanup step has 300 ms, cut short if the cleanup budget runs out. A speech model has 2 seconds per part. A cleanup model has what is left of 1.5 seconds after the user stops talking. Prefer local, fast models. On failure or timeout Voz falls back to its built-in models
- The default export has 3 seconds to finish. Register handlers there and do nothing slow
- `ctx.generate({ prompt, instructions, schema })` returns JSON from Apple's on-device model that fits a JSON schema (`object`, `array`, `string` with `enum`, `number`, `integer`, `boolean`). Use it in commands to turn speech into fields. Pass today's date and valid names in the prompt. It takes 1 to 3 seconds
- `ctx.transcribe(path, { speakers: true })` transcribes an audio or video file with Parakeet and splits it into speaker turns. It fixes words from the user's dictionary, and the notch shows that Voz is transcribing. Use it in `voz.on("audioDrop", ...)`, which runs when the user drops an audio or video file on the notch
- `await activity.transcribeLive({ systemAudio: true, speakers: true, onTranscript })` records the microphone, plus everything the Mac plays with `systemAudio`, and calls `onTranscript` with the whole transcript so far, a few seconds behind speech. Replace what you saved before, because earlier turns can change. `stop()` on the result returns the whole transcript. Recording stops when the activity ends
- `ctx.ask({ title, fields, buttons })` shows a card under the notch and waits for a button. Fields are `text`, `date` (milliseconds) or `choice` with `options`. It returns `{ button, values }`, or `null` when the user closes it. Use it to confirm an action that is hard to undo, and let the user fix the fields first
- `ctx.openNote({ title, text, onChange })` opens a small note the user can move. `onChange` gets the full text after the user pauses typing. Open it from an activity's `open`
- Give feedback with `ctx.notify("Sent to Linear")`. It shows a short message under the menu bar. Await your work first: `ctx` calls after a handler returns do nothing
- Anything the user may want to change is a setting. Declare it with `voz.settings({ key: { type, title, default } })`. `type` is `string`, `number` or `boolean`. A string can have `options` for a picker, `secret: true` for a token, or `required: true` when the extension can't work without it. Never ask the user to edit `settings.json`
- Write files to `voz.paths.data`, never next to the extension, or Voz reloads it on every write
- A package sets `"voz": { "apiVersion": 7 }` in `package.json`, the oldest API it needs. `voz new` writes the current one. To use a member added later, check for it, such as `if (ctx.ask)`, and keep `apiVersion` low so older Voz versions still load the package
- The user turns extensions on or off in the Extensions page, or with `voz enable <name>` and `voz disable <name>`. Don't build your own on/off switch
- Log with `console.log`. Read it with `voz logs --extensions`, or watch it in `voz dev`
- Use Bun and Node APIs (`fetch`, `Bun.spawn`, `node:fs`). Files in `~/.voz/extensions` can't import npm packages. If you need one, make a folder with a `package.json` and an `index.ts`, then run `voz install ./that-folder`
- Never read or send transcripts anywhere the user didn't ask for

## Test

Voz loads a file in `~/.voz/extensions` as soon as you save it. Dictate in any app to try it.

Control the running Voz from the terminal. Run `voz help` for every command:

- `voz start`, `voz status`: open Voz, then check permissions, the speech model and which extensions loaded
- `voz logs --extensions --since 5m`: what extensions logged, including load errors. Add `--follow` to keep watching
- `voz help <words>`: find a command, such as `voz help vocabulary`
- `voz extensions`: what is installed, whether it loaded, its error, commands and settings
- `voz config <name> [key] [value]`: read or change an extension's settings. Pass `-` as the value to read a token from stdin
- `voz enable <name>`, `voz disable <name>`: turn an extension on or off
- `voz <name> <id>`: run a tool or an action, such as `voz jira issues VOZ`. The `voz-` prefix is optional. Add `--help` for its flags
- `voz commands --json`: every command with its input schema
- `voz history [words] --limit 5`, `voz last`: what the user dictated
- `voz settings [key] [value]`: Voz's own settings
- `voz vocabulary list|add|remove`, `voz dictation start|stop`: the user's words and recording. `voz dictation stop --print` prints the text instead of typing it

To start an extension the user wants to share, run `voz new voz-<name>` in the folder where they keep code, then `voz dev voz-<name>`. Voz loads it, reloads it on save, prints its logs and writes the types to `voz.d.ts` in that folder.

## Share

Run `npm publish` in a folder made with `voz new`. Its `package.json` already has `"keywords": ["voz-package"]`, so it shows up in the Extensions page. Others install it with `voz install <name>`.
