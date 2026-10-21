# Extensions

Extensions are TypeScript or JavaScript modules that change what Voz does with your dictation. Voz runs them with Bun in a separate process. If an extension crashes or hangs, dictation keeps working.

## Write an extension

Put a file in `~/.voz/extensions`. Voz loads every `.ts` and `.js` file there, and every folder with an `index.ts` or `index.js`, in alphabetical order.

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.on("beforeInsert", (event, ctx) => {
    if (ctx.app.bundleID !== "com.tinyspeck.slackmacgap") return;
    return { text: event.text.replace(/\bjira (\d+)/gi, "JIRA-$1") };
  });

  voz.registerCommand("send it", (event, ctx) => ctx.press("return"));
});
```

Voz writes the types to `~/.voz/node_modules/voz`, so editors type-check files in `~/.voz/extensions`. It also writes `~/.voz/AGENTS.md`, a guide for coding agents. Open a coding agent in `~/.voz` and describe the extension you want. The factory can be `async`. Voz waits for it before it loads the next extension.

Voz reloads extensions when you save a file in `~/.voz/extensions`, a local package or `~/.voz/settings.json`, and when you install, remove or update a package. If an extension fails to load, Voz shows its name under the menu bar. Keep an extension's own files in `voz.paths.data`, not next to its code, or every write reloads it.

To work on an extension or package in another folder, run:

```
voz dev ./my-extension
```

Voz loads it, reloads it on save and prints extension logs, including `console.log`. It also writes the types to `node_modules/voz` in that folder, so your editor type-checks it. Press Ctrl-C to unload it.

## API

| Member                                 | What it does                                                                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `voz.on("beforeCleanup", handler)`     | Runs before the on-device model cleans up the text. Return `{ prompt }` to change the cleanup prompt for this dictation. Handlers run in load order, and each one gets the previous one's prompt. |
| `voz.on("beforeInsert", handler)`      | Runs before Voz inserts text. Return `{ text }` to replace it, or `{ handled: true }` to insert nothing and skip the remaining handlers. Handlers run in load order, and each one gets the previous one's text. |
| `voz.on("recording", handler)`         | Runs after each recording with a 16 kHz mono WAV file. Voz deletes the file after all handlers finish. Voz does not wait for it. |
| `voz.on("afterInsert", handler)`       | Runs after Voz inserts text. Voz does not wait for it. |
| `voz.registerCommand(phrase, handler)` | Runs `handler` when a dictation ends with `phrase`. Voz inserts the words before the phrase, then runs the command.                   |
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

`ctx` has:

- `ctx.app`: `bundleID` and `name` of the front app
- `ctx.insert(text)`: inserts text into the front app
- `ctx.press(key)`: presses a key, such as `"return"`, `"cmd+return"` or `"shift+tab"`. Modifiers: `cmd`, `shift`, `opt`, `ctrl`
- `ctx.notify(text)`: shows a short message under the menu bar

The types are in [`Resources/Extensions/voz.d.ts`](Resources/Extensions/voz.d.ts).

Extensions can use any Bun or Node API, such as `fetch`, `Bun.spawn` and `node:fs`.

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

## Limits

- All `beforeCleanup` handlers together have 300 ms, and so do all `beforeInsert` handlers. After that, Voz uses the prompt or text it had
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
voz install npm:voz-jira
voz install git:github.com/user/voz-jira@v1.0.0
voz install ./my-package
voz list
voz update
voz dev ./my-package
voz remove voz-jira
```

- npm installs use the exact version. `voz install npm:voz-jira@1.2.0` and `git:...@v1.0.0` are pinned. A git ref is a tag or a branch. `voz update` skips pinned packages and moves the others to the latest version
- Packages only change when you run `voz update`. Voz never updates them on its own
- Voz never runs install scripts
- Installed packages are listed in `~/.voz/settings.json`

## Settings file

```json
{
  "packages": ["npm:voz-jira", "git:github.com/user/voz-slack"],
  "config": {
    "voz-jira": { "project": "VOZ" }
  }
}
```

## Bun

The first time you install a package, or open Voz with an extension in `~/.voz/extensions`, Voz downloads Bun 1.4.3 into `~/Library/Application Support/voz/bun`. Voz checks the download's SHA-256 before using it. If you have no extensions, Voz does not download Bun.

## Security

Extensions run with your user's permissions. They can read your transcripts, your recordings, your files and the network. Voz does not sandbox them. Install only packages you trust, and read the source first.

To limit risk, Voz:

- Never runs install scripts, so installing a package does not run its code
- Installs exact versions and updates only when you run `voz update`
- Pins packages to a version or git ref when you ask
