# Extensions

> Extensions are TypeScript modules that change what Voz does with a dictation. Voz runs them with Bun in a separate process, so a crashed or slow extension never stops dictation. This file is the full guide, written so a coding agent can read it and build an extension with you.

## Build one with a coding agent

Paste this into Claude Code, Codex, Cursor or any coding agent, and replace the last line:

```
Read https://raw.githubusercontent.com/Joelheile/voz/main/EXTENSIONS.md and follow
"Instructions for agents" to build a Voz extension with me.
My idea: <one sentence, such as "send Slack messages when I say send it">
```

The agent interviews you first, then builds, loads and tests the extension with you.

## Instructions for agents

You help a Voz user turn an idea into a working extension. The user knows what bothers them about dictating. You know the API in this file. Together you find the smallest extension that fixes their problem.

### What extensions are for

Voz stays small: record, transcribe, clean up, insert. Extensions add everything personal on top, such as voice commands, per-app writing styles, other speech or cleanup models, and buttons that send text to other tools. A good extension:

- Does one job the user can describe in a sentence
- Fits the time budget of the hook it uses (see [Limits](#limits))
- Fails quietly: Voz falls back to its built-in behavior, and the user keeps dictating
- Sends transcripts only where the user asked for them
- Exposes every value the user may want to change as a [setting](#settings)

### Step 1: Interview the user

Grill the user until you share one picture of the extension. Map the idea as a design tree, where each decision opens the decisions that depend on it. Ask in rounds. Each round holds every question you can ask now without guessing an earlier answer. Number the questions, give your recommended answer for each, and word each one so "yes" accepts your recommendation. Use your agent's question tool if it has one. Wait for the answers, then ask the next round.

Work through these branches. Skip any the user already answered.

1. **Trigger.** What starts it: a spoken phrase at the end of a dictation, every dictation, dictation in certain apps, a button or a hotkey?
2. **Scope.** Which apps? Find their bundle IDs yourself with `osascript -e 'id of app "Slack"'`.
3. **Effect.** What changes: the words Voz types, how the cleanup model writes, something outside Voz (an API, a file, a key press), or the model itself?
4. **Examples.** Ask for two or three real dictations and the exact result the user wants for each. These become your tests.
5. **Setup.** Which tokens, URLs or choices does the user configure? Each one is a setting.
6. **Feedback.** How does the user know it worked? Usually `ctx.notify`.
7. **Failure.** What should happen when the network or a service is down?
8. **Sharing.** A private file in `~/.voz/extensions`, or a package to publish?

Look up facts yourself instead of asking: run `voz list`, read `~/.voz/settings.json` and `~/.voz/extensions`, read the API docs of the service the user names.

The interview is done when you can state the extension in one sentence that names its trigger, the API members it uses, its output and its settings, and the user says yes to that sentence.

### Step 2: Pick the API members

| The user wants                                                            | Use                                                                             |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| A spoken phrase that does something, such as "send it" or "make a ticket" | [`registerCommand`](#api)                                                       |
| A dictation that becomes data, such as "todo call Milan tomorrow"         | `registerCommand` with `{ at: "start" }` and [`ctx.generate`](#on-device-model) |
| A different writing style in some apps                                    | `beforeCleanup`, adding to the prompt ([example](#per-app-prompts))             |
| A fixed text rule, such as a regex or word replacement                    | [`registerCleanupStep`](#models-and-cleanup-steps)                              |
| The final say over what gets typed, or to type nothing                    | `beforeInsert`                                                                  |
| Dictations saved or sent somewhere after they are typed                   | `afterInsert`                                                                   |
| The audio itself                                                          | `recording`                                                                     |
| A different speech-to-text or cleanup model                               | [`registerSpeechModel` or `registerCleanupModel`](#models-and-cleanup-steps)    |
| A button in the Voz panel, or a global hotkey                             | [`registerAction`](#actions)                                                    |

Put network calls and model calls in commands, actions, `afterInsert` or a registered model. `beforeCleanup`, `beforeInsert` and cleanup steps get 300 ms, enough for string work only.

### Step 3: Build the smallest version

- For a private extension, write one file in `~/.voz/extensions`, such as `~/.voz/extensions/slack-send.ts`. Voz loads it on save.
- For one to share, or one that needs npm packages, run `voz new voz-<name>` in the user's code folder, then `voz dev voz-<name>`.
- If `voz` is not on the PATH, use `/Applications/voz.app/Contents/MacOS/voz`.
- Read the types in `~/.voz/node_modules/voz/index.d.ts`, or `voz.d.ts` in a package, before you write code.
- Keep pure text logic in its own function so you can test it without Voz.

### Step 4: Verify

1. Test the pure logic with `bun test`, using the user's examples from the interview. If `bun` is not on the PATH, use the copy Voz downloads to `~/Library/Application Support/voz/bun/<version>/bun`.
2. Load the extension. `voz dev` prints load errors and logs. For a loose file, a failed load shows the extension's name under the menu bar.
3. Ask the user to dictate each example and tell you what Voz typed or did. Fix and repeat until every example gives the result the user asked for.

Done means: the extension loads without errors, every example passes, and the user confirmed it in a real dictation.

### Step 5: Hand over

Tell the user how to trigger it, which settings to fill in under Extensions in the Voz panel, and how to turn it off. For a package, explain how to publish it (see [Packages](#packages)).

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
    greeting: {
      type: "string",
      title: "Greeting",
      default: "Hello from voz-hello",
    },
  });

  voz.registerCommand("say hello", (event, ctx) =>
    ctx.notify(settings.greeting),
  );
});
```

To share it, run `npm publish` in the folder. Anyone can then install it with `voz install voz-hello`, or open `voz://extensions/voz-hello` to see it in Voz with an Install button. The `voz-package` keyword in `package.json` lists it in the Extensions page and on [voz.joels.tech/extensions](https://voz.joels.tech/extensions/).

`voz dev` writes `voz.d.ts` again each time, so the types match the Voz you run. In a folder you did not create with `voz new`, add `"paths": { "voz": ["./voz.d.ts"] }` to `compilerOptions` in `tsconfig.json`.

## Loose files

For a quick change you do not plan to share, put a file in `~/.voz/extensions`. Voz loads every `.ts` and `.js` file there, and every folder with an `index.ts` or `index.js`, in alphabetical order. Voz writes the types to `~/.voz/node_modules/voz`, so editors type-check these files.

The factory can be `async`. Voz waits for it before it loads the next extension.

Voz reloads extensions when you save a file in `~/.voz/extensions`, a local package or `~/.voz/settings.json`, and when you install, remove or update a package. If an extension fails to load, Voz shows its name under the menu bar. Keep an extension's own files in `voz.paths.data`, not next to its code, or every write reloads it.

## API

| Member                                          | What it does                                                                                                                                                                                                                                          |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `voz.on("beforeCleanup", handler)`              | Runs before the on-device model cleans up the text. Return `{ prompt }` to change the cleanup prompt for this dictation. Handlers run in load order, and each one gets the previous one's prompt.                                                     |
| `voz.on("beforeInsert", handler)`               | Runs before Voz inserts text. Return `{ text }` to replace it. Return `{ text: "" }` to insert nothing and skip the remaining handlers. Handlers run in load order, and each one gets the previous one's text.                                        |
| `voz.on("recording", handler)`                  | Runs after each recording with a 16 kHz mono WAV file. Voz deletes the file after all handlers finish. Voz does not wait for it.                                                                                                                      |
| `voz.on("afterInsert", handler)`                | Runs after Voz inserts text. Voz does not wait for it.                                                                                                                                                                                                |
| `voz.registerSpeechModel(model)`                | Adds a speech model to Settings. `model` has `id`, `name` and `transcribe(event, ctx)`, which returns `{ text }`.                                                                                                                                     |
| `voz.registerCleanupModel(model)`               | Adds a cleanup model to Settings. `model` has `id`, `name` and `clean(event, ctx)`, which returns `{ text }`.                                                                                                                                         |
| `voz.registerCleanupStep(step)`                 | Adds a cleanup step you can turn on in the extension's details. `step` has `id`, `name` and `run(event, ctx)`, which returns `{ text }` or nothing to keep the text.                                                                                  |
| `voz.registerCommand(phrase, handler, options)` | Runs `handler` when a dictation ends with `phrase`. Voz inserts the words before the phrase, then runs the command. With `{ at: "start" }`, it runs when a dictation starts with `phrase`: Voz inserts nothing and passes the words after the phrase. Packages that use `at` set `"voz": { "apiVersion": 2 }`. |
| `voz.registerAction(action)`                    | Adds a button to the Actions group in the Voz panel. `action` has `id`, `name`, an optional `hotkey` such as `"ctrl+opt+j"`, and `run(ctx)`.                                                                                                          |
| `voz.settings(schema)`                          | Adds a settings form to the extension's row in the Extensions page, and returns the values. See [Settings](#settings).                                                                                                                                |
| `voz.name`                                      | The extension name: the file name, or the package name.                                                                                                                                                                                               |
| `voz.paths`                                     | `data` is `~/.voz/data/<name>`, a folder for the extension's own files.                                                                                                                                                                               |

Every handler gets `(event, ctx)`.

- The `beforeCleanup` event has `prompt`, the prompt from Settings
- The `beforeInsert` event has `text` (cleaned) and `raw` (before cleanup)
- The `recording` event has `path` and `seconds`
- The `afterInsert` event has `text` (what Voz inserted) and `raw`
- The command event has `text`, the words before the phrase, or after it for a start command
- The `transcribe` event has `path`, a 16 kHz mono WAV of one stretch of speech, and `seconds`
- The `clean` event has `text` and `prompt`, the cleanup prompt with your dictionary words
- The cleanup step event has `text`

`ctx` has:

- `ctx.app`: `bundleID` and `name` of the front app
- `ctx.insert(text)`: inserts text into the front app
- `ctx.press(key)`: presses a key, such as `"return"`, `"cmd+return"` or `"shift+tab"`. Modifiers: `cmd`, `shift`, `opt`, `ctrl`
- `ctx.notify(text)`: shows a short message under the menu bar
- `ctx.generate({ prompt, instructions, schema })`: asks Apple's on-device model for JSON that fits `schema`. See [On-device model](#on-device-model)

The types are in [`Resources/Extensions/voz.d.ts`](Resources/Extensions/voz.d.ts).

Extensions can use any Bun or Node API, such as `fetch`, `Bun.spawn` and `node:fs`.

## On-device model

`ctx.generate` runs Apple's on-device model, the same one Voz uses for cleanup. Nothing leaves the Mac. Use it to turn a dictation into fields:

```ts
voz.registerCommand(
  "todo",
  async (event, ctx) => {
    const todo = await ctx.generate({
      instructions: "Extract a to-do. Keep the title short.",
      prompt: event.text,
      schema: {
        type: "object",
        properties: {
          title: { type: "string", description: "Short to-do title" },
          when: { type: "string", enum: ["today", "tomorrow", "someday"] },
          checklist: { type: "array", items: { type: "string" } },
        },
        required: ["title"],
      },
    });
    ctx.notify(`Added ${todo.title}`);
  },
  { at: "start" },
);
```

- `schema` is a subset of JSON Schema: `object` with `properties` and `required`, `array` with `items`, `string` with an optional `enum`, `number`, `integer` and `boolean`. Each one can have a `description`, which the model reads
- The result is typed from the schema. Properties not in `required` may be missing. A `required` name that is not in `properties` rejects the call
- Voz orders the output the way you order `properties`. Put the fields the model should decide first at the top
- The model is small. Give it the facts it can't know, such as today's date or the list of valid names, and use `enum` for fixed choices. Do date math in code
- It takes one to three seconds, so call it in a command, an action or `afterInsert`. It fails if the handler's time runs out, or if Apple Intelligence is off
- Packages that call it set `"voz": { "apiVersion": 2 }`

## Settings

`voz.settings(schema)` describes the settings your extension has. Voz shows them as a form in the Extensions page, and returns the current values with your defaults filled in.

```ts
const settings = voz.settings({
  project: { type: "string", title: "Jira project", default: "VOZ" },
  tone: {
    type: "string",
    title: "Tone",
    default: "casual",
    options: ["casual", "formal"],
  },
  token: {
    type: "string",
    title: "API token",
    default: "",
    secret: true,
    required: true,
  },
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

An extension that registers a model or step only makes it available. You turn on a model in Settings and a step in the extension's details under Extensions, or either one in `~/.voz/settings.json`. Settings shows the step order once an extension adds a step. Voz names it `<extension name>/<id>`.

```ts
import { defineExtension } from "voz";

export default defineExtension((voz) => {
  voz.registerCleanupModel({
    id: "llama",
    name: "Llama 3.2",
    async clean(event) {
      const response = await fetch("http://localhost:11434/api/generate", {
        method: "POST",
        body: JSON.stringify({
          model: "llama3.2",
          system: event.prompt,
          prompt: event.text,
          stream: false,
        }),
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
- A command has 10 seconds, including the time `ctx.generate` takes. `recording` and `afterInsert` handlers have 30 seconds
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
- A package that needs a newer Voz sets `"voz": { "apiVersion": 2 }` in its `package.json`. Older Voz versions show "Update Voz" instead of loading it. Within one API version, Voz only adds to the API and never changes or removes what is there. Packages that declare API 1, or no version, still get what API 2 removed: `voz.config`, `voz.log`, `voz.events`, `voz.paths.home` and `{ handled: true }` from `beforeInsert`. New code uses `voz.settings`, `console.log` and `{ text: "" }`. `import { apiVersion } from "voz"` gives the version that runs

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
  "cleanupSteps": [
    "fillers",
    "punctuation",
    "dictionary",
    "model",
    "voz-jira/jira"
  ]
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
