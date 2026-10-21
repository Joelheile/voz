# Extensions

Extensions are TypeScript or JavaScript modules that change what Voz does with your dictation. Voz runs them with Bun in a separate process. If an extension crashes or hangs, dictation keeps working.

## Quick start

```
voz new voz-hello
voz dev voz-hello
```

`voz new` creates a package in `./voz-hello` with `index.ts`, `package.json`, a README and the Voz types in `voz.d.ts`. `voz dev` loads it, reloads it when you save and prints its logs, including `console.log`. Say "say hello" at the end of a dictation to run its command. Press Ctrl-C to unload it.

The template adds a setting and a command:

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  const settings = voz.settings({
    greeting: { type: "string", title: "Greeting", default: "Hello from voz-hello" },
  });

  voz.registerCommand("say hello", (event, ctx) => ctx.notify(settings.greeting));
});
```

To share it, run `npm publish` in the folder. Anyone can then install it with `voz install voz-hello`, or open `voz://extensions/voz-hello` to see it in Voz with an Install button. The `voz-package` keyword in `package.json` lists it in the Extensions page and on [voz.joels.tech/extensions](https://voz.joels.tech/extensions/).

`voz dev` writes `voz.d.ts` again each time, so the types match the Voz you run. In a folder you did not create with `voz new`, add `"paths": { "voz": ["./voz.d.ts"] }` to `compilerOptions` in `tsconfig.json`.

## Loose files

For a quick change you do not plan to share, put a file in `~/.voz/extensions`. Voz loads every `.ts` and `.js` file there, and every folder with an `index.ts` or `index.js`, in alphabetical order. Voz writes the types to `~/.voz/node_modules/voz`, so editors type-check these files. It also writes `~/.voz/AGENTS.md`, a guide for coding agents. Open a coding agent in `~/.voz` and describe the extension you want.

The factory can be `async`. Voz waits for it before it loads the next extension.

Voz reloads extensions when you save a file in `~/.voz/extensions`, a local package or `~/.voz/settings.json`, and when you install, remove or update a package. If an extension fails to load, Voz shows its name under the menu bar. Keep an extension's own files in `voz.paths.data`, not next to its code, or every write reloads it.

## API

| Member                                 | What it does                                                                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `voz.on("beforeCleanup", handler)`     | Runs before the on-device model cleans up the text. Return `{ prompt }` to change the cleanup prompt for this dictation. Handlers run in load order, and each one gets the previous one's prompt. |
| `voz.on("beforeInsert", handler)`      | Runs before Voz inserts text. Return `{ text }` to replace it, or `{ handled: true }` to insert nothing and skip the remaining handlers. Handlers run in load order, and each one gets the previous one's text. |
| `voz.on("recording", handler)`         | Runs after each recording with a 16 kHz mono WAV file. Voz deletes the file after all handlers finish. Voz does not wait for it. |
| `voz.on("afterInsert", handler)`       | Runs after Voz inserts text. Voz does not wait for it. |
| `voz.registerSpeechModel(model)`       | Adds a speech model to Settings. `model` has `id`, `name` and `transcribe(event, ctx)`, which returns `{ text }`. |
| `voz.registerCleanupModel(model)`      | Adds a cleanup model to Settings. `model` has `id`, `name` and `clean(event, ctx)`, which returns `{ text }`. |
| `voz.registerCleanupStep(step)`        | Adds a cleanup step to Settings. `step` has `id`, `name` and `run(event, ctx)`, which returns `{ text }` or nothing to keep the text. |
| `voz.registerCommand(phrase, handler)` | Runs `handler` when a dictation ends with `phrase`. Voz inserts the words before the phrase, then runs the command.                   |
| `voz.registerAction(action)`           | Adds a button to the Actions group in the Voz panel. `action` has `id`, `name`, an optional `hotkey` such as `"ctrl+opt+j"`, and `run(ctx)`. |
| `voz.settings(schema)`                 | Adds a settings form to the extension's row in the Extensions page, and returns the values. See [Settings](#settings). |
| `voz.config`                           | The object at `config.<extension name>` in `~/.voz/settings.json`.                                                                    |
| `voz.log(message)`                     | Writes to the Voz log. `console.log` does the same.                                                                                   |
| `voz.name`                             | The extension name: the file name, or the package name.                                                                               |
| `voz.paths`                            | `home` is `~/.voz`. `data` is `~/.voz/data/<name>`, a folder for the extension's own files. |
| `voz.events`                           | `on(name, handler)` and `emit(name, data)`. Extensions use it to talk to each other. |

Every handler gets `(event, ctx)`.

- The `beforeCleanup` event has `prompt`, the prompt from Settings
- The `beforeInsert` event has `text` (cleaned) and `raw` (before cleanup)
- The `recording` event has `path` and `seconds`
- The `afterInsert` event has `text` (what Voz inserted) and `raw`
- The command event has `text`, the words before the phrase
- The `transcribe` event has `path`, a 16 kHz mono WAV of one stretch of speech, and `seconds`
- The `clean` event has `text` and `prompt`, the cleanup prompt with your dictionary words
- The cleanup step event has `text`

`ctx` has:

- `ctx.app`: `bundleID` and `name` of the front app
- `ctx.insert(text)`: inserts text into the front app
- `ctx.press(key)`: presses a key, such as `"return"`, `"cmd+return"` or `"shift+tab"`. Modifiers: `cmd`, `shift`, `opt`, `ctrl`
- `ctx.notify(text)`: shows a short message under the menu bar

The types are in [`Resources/Extensions/voz.d.ts`](Resources/Extensions/voz.d.ts).

Extensions can use any Bun or Node API, such as `fetch`, `Bun.spawn` and `node:fs`.

## Settings

`voz.settings(schema)` describes the settings your extension has. Voz shows them as a form in the Extensions page, and returns the current values with your defaults filled in.

```ts
const settings = voz.settings({
  project: { type: "string", title: "Jira project", default: "VOZ" },
  tone: { type: "string", title: "Tone", default: "casual", options: ["casual", "formal"] },
  token: { type: "string", title: "API token", default: "", secret: true, required: true },
  limit: { type: "number", title: "Results", default: 5 },
  enabled: { type: "boolean", title: "Send on save", default: true },
});
```

- Each setting has `type` (`string`, `number` or `boolean`), `title`, `default` and an optional `description`
- A string with `options` shows a picker. A string with `secret` hides what you type
- A string with `required` shows "Needs setup" on the extension's row until the user fills it in
- Voz saves the values under `config.<extension name>` in `~/.voz/settings.json` and reloads the extension when they change
- A missing value, or one of the wrong type, gives the default. The values are typed, so `settings.limit` is a `number`
- A setting with an unknown `type`, no `title` or a `default` of the wrong type fails the extension's load with an error

`~/.voz/settings.json` is a plain file. Do not keep secrets there that you would not keep in your shell profile.

## Actions

An action is a button in the Voz panel, with an optional global hotkey.

```ts
voz.registerAction({
  id: "board",
  name: "Open Jira board",
  hotkey: "ctrl+opt+j",
  run: (ctx) => {
    Bun.spawn(["open", `https://jira.example.com/browse/${settings.project}`]);
  },
});
```

The hotkey uses the same keys as `ctx.press`. If another app holds the hotkey, Voz shows a message and the button still works. An action has 10 seconds, like a command.

## Per-app prompts

You edit the cleanup prompt in Settings, under Cleanup prompt. To use a different prompt per app, add to it in `beforeCleanup`:

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.on("beforeCleanup", (event, ctx) => {
    if (ctx.app.bundleID !== "com.tinyspeck.slackmacgap") return;
    return { prompt: event.prompt + "\n\nWrite casually. Use lowercase." };
  });
});
```

## Models and cleanup steps

Voz runs each dictation through a speech model, then through cleanup steps in order. The built-in steps are `fillers`, `punctuation`, `dictionary` and `model`. The `model` step uses the cleanup model.

An extension that registers a model or step only makes it available. You turn it on in Settings, or in `~/.voz/settings.json`. Voz names it `<extension name>/<id>`.

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCleanupModel({
    id: "llama",
    name: "Llama 3.2",
    async clean(event) {
      const response = await fetch("http://localhost:11434/api/generate", {
        method: "POST",
        body: JSON.stringify({ model: "llama3.2", system: event.prompt, prompt: event.text, stream: false }),
      });
      return { text: (await response.json()).response };
    },
  });

  voz.registerCleanupStep({
    id: "jira",
    name: "Jira keys",
    run: (event) => ({ text: event.text.replace(/\bjira (\d+)/gi, "JIRA-$1") }),
  });
});
```

Voz splits a dictation at pauses and transcribes and cleans up each part while you talk. A speech model or cleanup step runs once per part.

## Limits

- All `beforeCleanup` handlers together have 300 ms, and so do all `beforeInsert` handlers. After that, Voz uses the prompt or text it had
- A speech model has 2 seconds per part. If it fails or runs over, Voz transcribes that part with Parakeet
- A cleanup model shares the cleanup budget with the other steps: Voz waits at most 1.5 seconds after you stop talking. If it fails, runs over or changes the meaning, Voz uses the text from the other steps
- A cleanup step has 300 ms, or less if the 1.5 second cleanup budget runs out first. If it fails or runs over, Voz keeps the text from the step before
- If the cleanup budget runs out before a part is done, Voz uses the built-in steps only for that part
- A command has 10 seconds. `recording` and `afterInsert` handlers have 30 seconds
- Each extension has 3 seconds to load. After that, Voz reports it as failed and loads the next one
- If a handler throws or a promise rejects unhandled, Voz logs the error and skips that handler
- If the extension process exits or stops answering for 2 seconds, Voz restarts it, up to 3 times in a row

## Packages

A package is a folder, git repo or npm package with extensions in it. Voz looks for them in this order:

1. The `voz.extensions` array in `package.json`, such as `{ "voz": { "extensions": ["src/main.ts"] } }`.
2. An `extensions` folder.
3. An `index.ts` or `index.js` file.

Voz does not read `main`. A package with none of these fails to load with an error.

Install and manage packages from the terminal. The `voz` binary is `/Applications/voz.app/Contents/MacOS/voz`.

```
voz install voz-jira
voz install git:github.com/user/voz-jira@v1.0.0
voz install ./my-package
voz new voz-jira
voz list
voz update
voz dev ./my-package
voz remove voz-jira
```

- A bare name such as `voz-jira` installs from npm. Local paths start with `./`, `/` or `~`
- npm installs use the exact version. `voz install voz-jira@1.2.0` and `git:...@v1.0.0` are pinned. A git ref is a tag or a branch. `voz update` skips pinned packages and moves the others to the latest version
- Packages only change when you run `voz update`. Voz never updates them on its own
- Voz never runs install scripts
- Installed packages are listed in `~/.voz/settings.json`
- A package that needs a newer Voz sets `"voz": { "apiVersion": 2 }` in its `package.json`. Older Voz versions show "Update Voz" instead of loading it. Within one API version, Voz only adds to the API and never changes or removes what is there. `import { apiVersion } from "voz"` gives the version that runs

## Settings file

```json
{
  "packages": ["npm:voz-jira", "git:github.com/user/voz-slack"],
  "disabled": ["voz-slack"],
  "config": {
    "voz-jira": { "project": "VOZ" }
  },
  "speechModel": "parakeet-ultra",
  "cleanupModel": "voz-ollama/llama",
  "cleanupSteps": ["fillers", "punctuation", "dictionary", "model", "voz-jira/jira"]
}
```

- `speechModel` is `parakeet-ultra`, `parakeet-english-v2`, `apple-speech` or an extension model. If the extension model is not loaded, Voz uses Parakeet Ultra
- `cleanupModel` is `apple` or an extension model. If the extension model is not loaded, Voz uses Apple's on-device model
- `disabled` lists extensions that stay installed but don't load. A package name turns off every extension in it. The Extensions page has one switch per package and per file in `~/.voz/extensions`, and writes this list. With every extension off, Voz starts no Bun process
- `cleanupSteps` lists the steps in the order they run. Leave a step out to turn it off

Settings writes these keys when you change them. Voz reads the file again when you save it, and restarts extensions only when something other than these keys changed.

## Bun

The first time you install a package, or open Voz with an extension in `~/.voz/extensions`, Voz downloads Bun 1.4.3 into `~/Library/Application Support/voz/bun`. Voz checks the download's SHA-256 before using it. If you have no extensions, Voz does not download Bun.

## Security

Extensions run with your user's permissions. They can read your transcripts, your recordings, your files and the network. Voz does not sandbox them. Install only packages you trust, and read the source first.

To limit risk, Voz:

- Never runs install scripts, so installing a package does not run its code
- Installs exact versions and updates only when you run `voz update`
- Pins packages to a version or git ref when you ask
