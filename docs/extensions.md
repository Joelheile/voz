# Extensions

Extensions are TypeScript or JavaScript modules that change what voz does with your dictation. voz runs them with Bun in a separate process. If an extension crashes or hangs, dictation keeps working.

## Write an extension

Put a file in `~/.voz/extensions`. voz loads every `.ts` and `.js` file there, and every folder with an `index.ts` or `index.js`, in alphabetical order.

```ts
export default function (voz) {
  voz.on("beforeInsert", (event) => {
    if (event.app.bundleID !== "com.tinyspeck.slackmacgap") return;
    return { text: event.text.replace(/\bjira (\d+)/gi, "JIRA-$1") };
  });

  voz.registerCommand("send it", (ctx) => ctx.press("return"));
}
```

voz reloads extensions when you install, remove or update a package. After you edit a file in `~/.voz/extensions`, quit and reopen voz.

## API

| Member                                 | What it does                                                                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `voz.on("beforeInsert", handler)`      | Runs before voz inserts text. Return `{ text }` to replace it. Handlers run in load order, and each one gets the previous one's text. |
| `voz.registerCommand(phrase, handler)` | Runs `handler` when a dictation ends with `phrase`. voz inserts the words before the phrase, then runs the command.                   |
| `voz.config`                           | The object at `config.<extension name>` in `~/.voz/settings.json`.                                                                    |
| `voz.log(message)`                     | Writes to the voz log. `console.log` does the same.                                                                                   |
| `voz.name`                             | The extension name: the file name, or the package name.                                                                               |

The `beforeInsert` event has `text` (cleaned), `raw` (before cleanup) and `app` (`bundleID` and `name` of the front app).

A command handler gets `ctx` with:

- `ctx.text`: the text inserted before the phrase.
- `ctx.app`: the front app.
- `ctx.insert(text)`: inserts text into the front app.
- `ctx.press(key)`: presses a key, such as `"return"`, `"cmd+return"` or `"shift+tab"`. Modifiers: `cmd`, `shift`, `opt`, `ctrl`.

The types are in [`Resources/Extensions/host.ts`](../Resources/Extensions/host.ts).

Extensions can use any Bun or Node API, such as `fetch`, `Bun.spawn` and `node:fs`.

## Limits

- All `beforeInsert` handlers together have 300 ms. After that, voz inserts the text it had.
- A command has 10 seconds.
- If a handler throws, voz logs the error and skips that handler.
- If the extension process exits, voz restarts it up to 3 times.

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
voz remove voz-jira
```

- Git installs with a tag or commit stay on that ref. `voz update` pulls git packages without a ref and runs `bun update` for npm packages.
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

Extensions run with your user's permissions. They can read your transcripts, your files and the network. Install only packages you trust, and read the source first.
