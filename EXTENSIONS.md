# Extensions

Extensions are TypeScript or JavaScript modules that change what voz does with your dictation. voz runs them with Bun in a separate process. If an extension crashes or hangs, dictation keeps working.

## Write an extension

Put a file in `~/.voz/extensions`. voz loads every `.ts` and `.js` file there, and every folder with an `index.ts` or `index.js`, in alphabetical order.

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

voz writes the types to `~/.voz/node_modules/voz`, so editors type-check files in `~/.voz/extensions`. The factory can be `async`. voz waits for it before it loads the next extension.

voz reloads extensions when you save a file in `~/.voz/extensions` or in a local package, and when you install, remove or update a package. Keep an extension's own files in `voz.paths.data`, not next to its code, or every write reloads it.

To work on an extension or package in another folder, run:

```
voz dev ./my-extension
```

voz loads it, reloads it on save and prints extension logs, including `console.log`. Press Ctrl-C to unload it.

## API

| Member                                 | What it does                                                                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `voz.on("beforeInsert", handler)`      | Runs before voz inserts text. Return `{ text }` to replace it, or `{ handled: true }` to insert nothing and skip the remaining handlers. Handlers run in load order, and each one gets the previous one's text. |
| `voz.on("recording", handler)`         | Runs after each recording with a 16 kHz mono WAV file. voz deletes the file after all handlers finish. voz does not wait for it. |
| `voz.on("afterInsert", handler)`       | Runs after voz inserts text. voz does not wait for it. |
| `voz.registerCommand(phrase, handler)` | Runs `handler` when a dictation ends with `phrase`. voz inserts the words before the phrase, then runs the command.                   |
| `voz.config`                           | The object at `config.<extension name>` in `~/.voz/settings.json`.                                                                    |
| `voz.log(message)`                     | Writes to the voz log. `console.log` does the same.                                                                                   |
| `voz.name`                             | The extension name: the file name, or the package name.                                                                               |
| `voz.paths`                            | `home` is `~/.voz`. `data` is `~/.voz/data/<name>`, a folder for the extension's own files. |
| `voz.events`                           | `on(name, handler)` and `emit(name, data)`. Extensions use it to talk to each other. |

Every handler gets `(event, ctx)`.

- The `beforeInsert` event has `text` (cleaned) and `raw` (before cleanup).
- The `recording` event has `path` and `seconds`.
- The `afterInsert` event has `text` (what voz inserted) and `raw`.
- The command event has `text`, the words before the phrase.

`ctx` has:

- `ctx.app`: `bundleID` and `name` of the front app.
- `ctx.insert(text)`: inserts text into the front app.
- `ctx.press(key)`: presses a key, such as `"return"`, `"cmd+return"` or `"shift+tab"`. Modifiers: `cmd`, `shift`, `opt`, `ctrl`.

The types are in [`Resources/Extensions/host.ts`](../Resources/Extensions/host.ts).

Extensions can use any Bun or Node API, such as `fetch`, `Bun.spawn` and `node:fs`.

## Limits

- All `beforeInsert` handlers together have 300 ms. After that, voz inserts the text it had.
- A command has 10 seconds. `recording` and `afterInsert` handlers have 30 seconds.
- If a handler throws, voz logs the error and skips that handler.
- If the extension process exits or stops answering for 2 seconds, voz restarts it, up to 3 times.

## Packages

A package is a folder, git repo or npm package with extensions in it. voz looks for them in this order:

1. The `voz.extensions` array in `package.json`, such as `{ "voz": { "extensions": ["src/main.ts"] } }`.
2. An `extensions` folder.
3. An `index.ts` or `index.js` file.

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

- npm installs use the exact version. `voz install npm:voz-jira@1.2.0` and `git:...@v1.0.0` are pinned. `voz update` skips pinned packages and moves the others to the latest version.
- Packages only change when you run `voz update`. voz never updates them on its own.
- voz never runs install scripts.
- Installed packages are listed in `~/.voz/settings.json`.

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

The first time you install a package, or open voz with an extension in `~/.voz/extensions`, voz downloads Bun 1.4.3 into `~/Library/Application Support/voz/bun`. voz checks the download's SHA-256 before using it. If you have no extensions, voz does not download Bun.

## Security

Extensions run with your user's permissions. They can read your transcripts, your recordings, your files and the network. voz does not sandbox them. Install only packages you trust, and read the source first.

To limit risk, voz:

- Never runs install scripts, so installing a package does not run its code.
- Installs exact versions and updates only when you run `voz update`.
- Pins packages to a version or git ref when you ask.
