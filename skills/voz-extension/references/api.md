# Voz extension API

The full API for Voz extensions. The exact types are in `voz.d.ts` in a package folder, or `~/.voz/node_modules/voz/index.d.ts` for files in `~/.voz/extensions`.

## Contents

- Quick start, Examples, Loose files
- API: every member, event and `ctx` call
- On-device model, Background work, Audio files, Settings, Lists, Actions, Tools
- Activities, Live transcription, Notes, Ask, Busy, Text fields, History
- Per-app prompts, Models and cleanup steps
- Limits: time budgets and what Voz does when they run out
- Packages, What the user wrote, What the user saw, Versions, Settings file, Bun, Security

## Quick start

```
voz new voz-hello
voz dev voz-hello
```

`voz new` creates a package in `./voz-hello` with `index.ts`, `package.json`, a README and the Voz types in `voz.d.ts`. `voz dev` loads it, reloads it when you save and prints its logs, including `console.log`. Voz also writes them to `~/Library/Logs/Voz/voz-logs.jsonl`, which you copy under Settings, Debug log. Say "say hello" at the end of a dictation to run its command. Press Ctrl-C to unload it.

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

  voz.registerCommand({
    phrase: "say hello",
    run: (event, ctx) => ctx.notify(settings.greeting),
  });
});
```

To share it, run `npm publish` in the folder. Anyone can then install it with `voz install voz-hello`, or open `voz://extensions/voz-hello` to see it in Voz with an Install button. The `voz-package` keyword in `package.json` lists it in the Extensions page and on [voz.tools/extensions](https://voz.tools/extensions/).

`voz dev` writes `voz.d.ts` again each time, so the types match the Voz you run. In a folder you did not create with `voz new`, add `"paths": { "voz": ["./voz.d.ts"] }` to `compilerOptions` in `tsconfig.json`.

## Examples

Each example is a published package you can install or copy as a starting point:

| Example                                                                      | What it does                                                      | API it shows                  |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------- | ----------------------------- |
| [voz-send-it](https://github.com/Joelheile/voz/tree/main/examples/send-it)   | Types the words before "send it", then presses Return             | `registerCommand`, `settings` |
| [voz-mail](https://github.com/Joelheile/voz/tree/main/examples/mail)         | Formats dictations in Mail or Outlook as an email                 | `beforeCleanup`, `settings`   |
| [voz-launcher](https://github.com/Joelheile/voz/tree/main/examples/launcher) | Runs dictations that start with "computer" instead of typing them | `beforeInsert`, `settings`    |
| [voz-edit](https://github.com/Joelheile/voz/tree/main/examples/edit)         | Changes what you just dictated when you say "edit shorter"        | `ctx.field`, `ctx.busy`, `afterInsert`, `voz.history` |
| [voz-reply](https://github.com/Joelheile/voz/tree/main/examples/reply)       | Drafts a reply in your tone from the conversation on screen       | `ctx.field`, `ctx.busy`, `voz.history`, `voz.screen` |
| [voz-replace](https://github.com/Joelheile/voz/tree/main/examples/replace)   | Replaces words and expands phrases such as "my email" into text   | `beforeInsert`, `registerList`, `registerTool`, `ctx.ask` |

## Loose files

For a quick change you do not plan to share, put a file in `~/.voz/extensions`. Voz loads every `.ts` and `.js` file there, and every folder with an `index.ts` or `index.js`, in alphabetical order. Voz writes the types to `~/.voz/node_modules/voz`, so editors type-check these files.

The factory can be `async`. Voz waits for it before it loads the next extension.

Voz reloads extensions when you save a file in `~/.voz/extensions`, a local package or `~/.voz/settings.json`, and when you install, remove or update a package. If an extension fails to load, Voz shows its name under the menu bar. Keep an extension's own files in `voz.paths.data`, not next to its code, or every write reloads it.

## API

An extension does four kinds of things. The kind sets how much time it gets:

| Kind      | Members                                                          | Time                                   |
| --------- | ---------------------------------------------------------------- | -------------------------------------- |
| Trigger   | `registerCommand`, `registerAction`, `registerTool`, `audioDrop` | Seconds to minutes. Full `ctx`         |
| Transform | `beforeCleanup`, `registerCleanupStep`, `beforeInsert`           | 300 ms. `ctx` has only `app`           |
| Provide   | `registerSpeechModel`, `registerCleanupModel`                    | The model budget, then Voz's own model |
| Observe   | `afterRecording`, `afterInsert`                                  | Up to 30 seconds. Voz does not wait    |

| Member                              | What it does                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `voz.on("beforeCleanup", handler)`  | Runs before Voz cleans up the text. Return `{ prompt }` to change the cleanup prompt, or `{ mode }` to change the cleanup mode, for this dictation. Handlers run in load order, and each one gets the previous one's prompt and mode.                                                                                                                                                                                                             |
| `voz.on("beforeInsert", handler)`   | Runs before Voz inserts text. Return `{ text }` to replace it. Return `{ text: "" }` to insert nothing and skip the remaining handlers. Handlers run in load order, and each one gets the previous one's text.                                                                                                                                                                                                                                    |
| `voz.on("afterRecording", handler)` | Runs after each recording with a 16 kHz mono WAV file. Voz deletes the file after all handlers finish. Voz does not wait for it.                                                                                                                                                                                                                                                                                                                  |
| `voz.on("afterInsert", handler)`    | Runs after Voz inserts text. Voz does not wait for it.                                                                                                                                                                                                                                                                                                                                                                                            |
| `voz.on("audioDrop", handler)`      | Runs when the user drops an audio or video file on the notch. While any extension listens, dragging such a file opens a drop zone in the notch. Without one, the notch ignores drags. See [Audio files](#audio-files).                                                                                                                                                                                                                            |
| `voz.registerSpeechModel(model)`    | Adds a speech model to Settings. `model` has `id`, `name` and `transcribe(event, ctx)`, which returns `{ text }`.                                                                                                                                                                                                                                                                                                                                 |
| `voz.registerCleanupModel(model)`   | Adds a cleanup model to Settings. `model` has `id`, `name` and `clean(event, ctx)`, which returns `{ text }`.                                                                                                                                                                                                                                                                                                                                     |
| `voz.registerCleanupStep(step)`     | Adds a cleanup step you can turn on in the extension's details. `step` has `id`, `name` and `run(event, ctx)`, which returns `{ text }` or nothing to keep the text.                                                                                                                                                                                                                                                                              |
| `voz.registerCommand(command)`      | Runs `command.run(event, ctx)` when a dictation ends with `command.phrase`. Voz inserts the words before the phrase, then runs the command. With `at: "start"`, it runs when a dictation starts with the phrase: Voz inserts nothing and passes the words after the phrase. With `at: "anywhere"` (API 7), it runs when the phrase appears anywhere: Voz inserts nothing and passes the whole dictation. Start beats end, and end beats anywhere. |
| `voz.registerAction(action)`        | Adds a button to the bottom row of the Voz panel. `action` has `id`, `name`, an optional `hotkey` such as `"ctrl+opt+j"`, `hidden`, an optional Lucide `icon` such as `"audio-lines"` and `run(ctx)`. Returns a handle with `update({ hidden })`. See [Actions](#actions).                                                                                                                                                                        |
| `voz.registerTool(tool)`            | Adds a command agents and the terminal run as `voz <extension> <id>`, and AI apps call over MCP. `tool` has `id`, `description`, an optional object schema `input`, `positional`, `readOnly` and `run(input, ctx)`, which returns JSON. See [Tools](#tools).                                                                                                                                                                                      |
| `voz.startActivity(activity)`       | Shows that something keeps running, with an optional Stop button. Returns `{ end(), stop(), transcribeLive(options) }`; `stop()` runs your `stop` handler as if the user pressed Stop. See [Activities](#activities).                                                                                                                                                                                                                                                                                                    |
| `voz.addHistory(entry)`             | Adds an entry to the Voz history, such as a meeting transcript. See [History](#history).                                                                                                                                                                                                                                                                                                                                                          |
| `voz.generate(request)`                         | Asks a model outside a handler, for background work such as learning. Takes the same request as `ctx.generate`, and `model: "on-device"` runs Apple's model whatever the user picked. See [Background work](#background-work).                       |
| `voz.registerList(list)`                        | Adds a list to the extension's page in Settings, such as what it learned, with a delete button on each row. See [Lists](#lists).                                                                                                                      |
| `voz.history(query)`                            | Reads what the user wrote through Voz: dictations, and drafts extensions inserted with what the user did with them. Read-only. See [What the user wrote](#what-the-user-wrote).                                                                       |
| `voz.screen()`                                  | Reads the text of the window in front. Needs `"screen": true` in `package.json`, and Voz shows that the extension reads the screen. Voz keeps nothing. See [What the user saw](#what-the-user-saw).                                                       |
| `voz.settings(schema)`              | Adds a settings form to the extension's row in the Extensions page, and returns the values. See [Settings](#settings).                                                                                                                                                                                                                                                                                                                            |
| `voz.name`                          | The extension name: the file name, or the package name.                                                                                                                                                                                                                                                                                                                                                                                           |
| `voz.paths`                         | `data` is `~/.voz/data/<name>`, a folder for the extension's own files.                                                                                                                                                                                                                                                                                                                                                                           |

Every handler gets `(event, ctx)`.

- The `beforeCleanup` event has `prompt`, the prompt from Settings, and `mode`, `"light"` or `"heavy"`. Light tells the cleanup model to only remove fillers and fix punctuation, so every other spoken word stays
- The `beforeInsert` event has `text` (cleaned) and `raw` (before cleanup)
- The `afterRecording` event has `path` and `seconds`
- The `afterInsert` event has `text` (what Voz inserted) and `raw`
- The `audioDrop` event has `path`, the dropped file
- The command event has `text`, the words before the phrase, or after it for a start command
- The `transcribe` event has `path`, a 16 kHz mono WAV of one stretch of speech, and `seconds`
- The `clean` event has `text` and `prompt`, the cleanup prompt with your dictionary words
- The cleanup step event has `text`

`ctx` has the members below. In `beforeCleanup`, `beforeInsert` and cleanup steps, `ctx` has only `app`, because the others take longer than those 300 ms allow.

- `ctx.app`: `bundleID` and `name` of the front app, and `website`, the hostname of the focused web page such as `github.com`. Voz reads it through Accessibility in Safari, Firefox and Chromium browsers, and never sends the path
- `ctx.insert(text, { instruction })`: inserts text into the front app. Voz saves it as a draft and watches what the user does with it. `instruction` is optional: what the user asked for. See [What the user wrote](#what-the-user-wrote)
- `ctx.press(key)`: presses a key, such as `"return"`, `"cmd+return"` or `"shift+tab"`. Modifiers: `cmd`, `shift`, `opt`, `ctrl`
- `ctx.notify(text)`: shows a short message under the menu bar
- `ctx.generate({ prompt, instructions, schema, model, effort })`: asks the user's AI model for JSON that fits `schema`. See [On-device model](#on-device-model)
- `ctx.models()`: lists the models the user's account offers and which one each tier runs
- `ctx.transcribe(path, { speakers })`: transcribes an audio or video file with Parakeet. See [Audio files](#audio-files)
- `ctx.openNote({ title, text, onChange })`: opens a Markdown note under the notch. See [Notes](#notes)
- `ctx.ask({ title, fields, buttons })`: shows a card under the notch and waits until the user presses a button. See [Ask](#ask)
- `ctx.field()`: reads the focused text field, its selection and the text around it. `ctx.select(range)` selects part of it, so `insert` replaces that part. See [Text fields](#text-fields)
- `ctx.busy(run)`: shows a working state in the notch that the user can cancel while `run` runs. See [Busy](#busy)

Extensions can use any Bun or Node API, such as `fetch`, `Bun.spawn` and `node:fs`.

## On-device model

`ctx.generate` runs the model the user picks under Settings > AI model. The first time you press an extension's hotkey, Voz asks you to pick ChatGPT, a Claude API key or Apple's on-device model. Apple's is the same one Voz uses for cleanup, and nothing leaves the Mac. You can switch later with `voz ai`. Voz keeps those sign-ins in the Keychain, so extensions never see them. Use it to turn a dictation into fields:

```ts
voz.registerCommand({
  phrase: "todo",
  at: "start",
  async run(event, ctx) {
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
});
```

- `schema` is a subset of JSON Schema: `object` with `properties` and `required`, `array` with `items`, `string` with an optional `enum`, `number`, `integer` and `boolean`. Each one can have a `description`, which the model reads
- The result is typed from the schema. Properties not in `required` may be missing. A `required` name that is not in `properties` rejects the call
- `model` picks a tier: `fast`, `balanced` (the default), `strong` or `max`. Each runs the newest model of that tier on the user's account, such as Haiku or Luna for `fast` and Opus or Sol for `strong`. Use `fast` for quick edits and `strong` for a reply someone will read
- `model` also takes an exact ID from `ctx.models()` or `voz models`. An ID from the provider the user didn't pick runs as the same tier, so `claude-opus-5-5` runs GPT-6.1 Sol for a ChatGPT user
- `effort: "low" | "medium" | "high"` lets the model think first. Leave it out for writing: the default is the least each model allows, which is fastest
- Apple's model ignores `model` and `effort`
- Voz orders the output the way you order `properties`. Put the fields the model should decide first at the top
- The model is small. Give it the facts it can't know, such as today's date or the list of valid names, and use `enum` for fixed choices. Do date math in code
- It takes one to three seconds, so call it in a command, an action or `afterInsert`. It fails if the handler's time runs out, or if Apple Intelligence is off

### Background work

`voz.generate` takes the same request as `ctx.generate` and runs outside a handler, such as on a timer. With `model: "on-device"`, it runs Apple's model whatever the user picked, so learning stays on the Mac and costs nothing. A small model can distill what the user does into short notes, and the user's picked model writes with them:

```ts
setInterval(async () => {
  const drafts = await voz.history({ source: voz.name, limit: 50 });
  const changed = drafts.filter((written) => written.outcome === "edited");
  if (changed.length === 0) return;
  const { rules } = await voz.generate({
    instructions: "List short rules about how the user changes drafts. Style only, never content.",
    prompt: changed.map((written) => `<draft>${written.output}</draft><sent>${written.text}</sent>`).join("\n"),
    schema: { type: "object", properties: { rules: { type: "array", items: { type: "string" } } }, required: ["rules"] },
    model: "on-device",
  });
  save(rules);
}, 5 * 60_000);
```

- It times out after 60 seconds, and fails when Apple Intelligence is off. Catch the error: learning can wait for the next run
- Apple's model reads about 4,000 tokens. Send a few short examples per call
- Without `model: "on-device"`, it runs the model the user picked, and the text goes to that provider

## Audio files

`ctx.transcribe(path, { speakers: true })` transcribes a whole audio or video file on the Mac with the Parakeet model picked in Settings. With `speakers`, Voz also finds who speaks when, with NVIDIA's Nemotron 3 diarization model, and splits the text into turns. It counts the speakers itself, up to 8.

```ts
voz.on("audioDrop", async ({ path }, ctx) => {
  const transcript = await ctx.transcribe(path, { speakers: true });
  for (const turn of transcript.turns)
    console.log(`${turn.start}s Speaker ${turn.speaker}: ${turn.text}`);
  ctx.notify(
    `${transcript.speakers} speakers, ${Math.round(transcript.seconds)} seconds`,
  );
});
```

- The result has `text`, `seconds`, `speakers` and `turns`. Each turn has `speaker` (1 is the first to talk), `start` and `end` in seconds, and `text`. Without `speakers`, all text is one turn
- Voz fixes words from the user's dictionary in `text` and in each turn, the same way it does for dictation
- The notch shows that Voz is transcribing until the call returns
- Voz reads the formats AVFoundation reads: audio such as MP3, M4A, WAV, AIFF and FLAC, and video such as MP4, MOV and M4V, where it uses only the sound. It rejects MKV and WebM
- It takes about a second per minute of audio, plus a few seconds the first time to load the models. The first diarization downloads a 95 MB model
- It fails when the user picked Apple speech in Settings
- Call it in `audioDrop`, a command or an action. If an `audioDrop` handler throws, the notch shows an error

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
- A string with `folder: true` shows a button that opens a folder picker. The value is the folder's full path. Expand a `~` in your default yourself
- A string with `required` shows "Needs setup" on the extension's row until the user fills it in
- Voz saves the values under `config.<extension name>` in `~/.voz/settings.json` and reloads the extension when they change
- A missing value, or one of the wrong type, gives the default. The values are typed, so `settings.limit` is a `number`
- A setting with an unknown `type`, no `title` or a `default` of the wrong type fails the extension's load with an error

`~/.voz/settings.json` is a plain file. Do not keep secrets there that you would not keep in your shell profile.

## Lists

`voz.registerList(list)` shows rows on the extension's page in Settings, such as what it learned about the user. Voz calls `items` when the page opens. With `remove`, each row gets a delete button:

```ts
voz.registerList({
  id: "style",
  title: "Writing style",
  description: "What Reply learned from your edits",
  items: () => notes.all().map((note) => ({ id: String(note.id), title: note.rule, detail: note.example })),
  remove: (id) => notes.delete(Number(id)),
});
```

- Each item has `id`, `title` and an optional `detail`
- Lists show only in Settings. To let agents and the terminal read and change the same rows, also register [tools](#tools)

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

The hotkey uses the same keys as `ctx.press`. If another app holds the hotkey, Voz shows a message and the button still works.

A hotkey can also be one modifier key tapped on its own: `"rightopt"`, `"leftopt"`, `"rightcmd"`, `"leftcmd"`, `"rightshift"`, `"leftshift"`, `"rightctrl"`, `"leftctrl"` or `"fn"`. A tap is a quick press and release with no other key or click in between, so typing with that modifier doesn't run it. Voz skips a tap on the user's dictation key.

Two actions can share a hotkey when `when` tells them apart. `when: "selection"` runs an action when text is selected in the focused field. The action without `when` runs otherwise. Without such an action, the hotkey runs the `when` action anyway, so a tap never does nothing. Reply and Edit share right Option this way:

```ts
voz.registerAction({ id: "edit", name: "Edit", hotkey: "rightopt", when: "selection", run: edit });
```

An action runs until it finishes, so it can record or transcribe for as long as it needs.

With an `icon`, the action is an icon in the panel's nav bar, next to Dictionary and Settings, and its name shows on hover. Without one, it is a button with its name. Every action also has a Run button in the extension's details on the Extensions page. Set `hidden: true` when the action does not apply right now, such as a setup step that is done. A hidden action leaves the panel, but stays in the details and keeps its hotkey. `registerAction` returns a handle. Call `update({ hidden })` when your state changes.

```ts
const connect = voz.registerAction({
  id: "connect",
  name: "Connect account",
  hidden: await isSignedIn(),
  run: async (ctx) => {
    await signIn();
    connect.update({ hidden: true });
  },
});
```

## Tools

A tool is a command for agents and the terminal. Voz checks the input against the schema, runs the tool, and prints what it returns.

```ts
voz.registerTool({
  id: "issues",
  description: "List my open Jira issues",
  readOnly: true,
  input: {
    type: "object",
    properties: {
      project: { type: "string", description: "Project key, such as VOZ" },
      limit: { type: "integer" },
    },
    required: ["project"],
  },
  positional: ["project"],
  run: async ({ project, limit }) => {
    const issues = await jira.search(`project = ${project}`, limit ?? 10);
    return issues.map(({ key, summary }) => ({ key, summary }));
  },
});
```

```
$ voz jira issues VOZ --limit 3
$ voz jira issues --input '{"project": "VOZ", "limit": 3}'
$ voz jira issues --help
$ voz jira
```

- Type the name as words or with slashes: `voz jira issues`, `voz voz-jira issues` and `voz voz-jira/issues` run the same tool. The `voz-` prefix is optional
- Group tools with `/` in the id. A tool with the id `issues/create` runs as `voz jira issues create`, and `voz jira issues` lists the group
- `positional` lists inputs you can type without a flag, in order. Every other input takes a flag, such as `--limit 3`
- Booleans take `--flag`, `--no-flag` or a value such as `on`, `off`, `yes` or `no`. Object and array inputs take JSON. `--input` takes the whole input as one JSON object, or `-` to read it from stdin

- `input` uses the same schema as [`ctx.generate`](#on-device-model). Leave it out when the tool takes no input. `run` gets the input typed from the schema
- Return any JSON value. People see a string as is, a list one item per line and an object as key and value lines. `--json` and agents get the JSON. Throw an error to fail: the caller gets its message
- Set `readOnly: true` when the tool changes nothing, so AI apps can call it without asking the user
- Agents see every tool in `voz commands --json`, with its input schema. `voz mcp` serves them to AI apps as `<extension>_<id>`, and opens Voz if it is closed
- A tool has 60 seconds to return. After that the caller gets an error, so return in seconds

Actions run the same way, as `voz <extension>/<action>`, without input.

### Design a tool

The agent calling your tool sees only its name, description and schema:

- Name tools with nouns and verbs a person would type: `issues`, `issues/create`. Group related tools under one noun
- Write the description as when to use it: "List my open Jira issues, newest first"
- Give every input a `description` with an example value. Put the one input people always pass in `positional`
- Return the few fields a caller needs, as a list of objects for many items, not the whole API response
- Throw an `Error` that says what to run next, such as "Set your Jira token with voz config voz-jira token -"
- Try it the way an agent will: `voz <name> <id> --help`, then `voz <name> <id> --json`

## Activities

An activity shows that something keeps running, such as a recording. While one runs, the Voz menu bar icon gets a dot, and the panel's nav bar shows how long it has run, with a Stop button.

```ts
const recording = voz.startActivity({
  title: "Recording meeting",
  stop: async (ctx) => {
    // stop the recorder, then transcribe
  },
});
// later, when it stops some other way
recording.end();
```

- `since` is when it started, in milliseconds like `Date.now()`. It defaults to now. Pass it when you start the activity again after a reload
- `stop` is optional. Without it, the panel shows no Stop button. Voz ends the activity, then runs `stop` with `ctx` and no time limit
- `open` is optional. With it, the notch shows the activity's timer while it runs, and clicking the notch, the floating pill on Macs without a notch, or Open in the Voz panel runs `open` with `ctx`. Use it to open a [note](#notes)
- An extension can run several activities at once. The notch shows the first one with `open`
- Voz ends all activities when it reloads extensions

### Live transcription

`transcribeLive` on a running activity records the microphone and transcribes it as the user talks. With `systemAudio`, Voz also records everything the Mac plays, such as the other people in a call, and mixes it with the microphone. With `speakers`, Voz splits the mix into speaker turns with NVIDIA's Nemotron 3 streaming diarization model.

```ts
const meeting = voz.startActivity({
  title: "Meeting",
  stop: async () => save(await live.stop()),
});
const live = await meeting.transcribeLive({
  systemAudio: true,
  speakers: true,
  onTranscript: (t) =>
    writeFileSync(
      file,
      t.turns.map((turn) => `Speaker ${turn.speaker}: ${turn.text}`).join("\n"),
    ),
});
```

- `onTranscript` gets the whole transcript so far, every 8 to 14 seconds, a few seconds behind speech. It has the same shape as [`ctx.transcribe`](#audio-files). Replace what you saved before: Voz can fix earlier turns as it hears more
- `stop()` returns the final transcript
- Recording stops when you call `stop()` or the activity ends. `stop()` still returns the transcript after the activity ended
- Voz fixes words from the user's dictionary
- It uses the microphone picked in Settings. The first time, macOS asks the user to allow Voz to record system audio. Without headphones, the microphone also hears the speakers, so other people's words can appear twice. Pass `you: true` with `systemAudio` to fix that, see below
- The first live diarization downloads a 190 MB model. It fails when the user picked Apple speech in Settings
- Voz keeps no audio
- When the microphone stops delivering, or the Mac switches its speakers, Voz restarts the recording on the current devices. A few seconds go missing, the transcript keeps going
- With `you: true` and `systemAudio`, Voz transcribes your microphone and the call apart. Your turns have `you: true` and `speaker` 0, the call's speakers count from 1. Words the microphone heard from the speakers within 1.5 seconds of the call drop out, so the call doesn't appear twice without headphones. It takes about twice the processing

```ts
const live = await meeting.transcribeLive({
  systemAudio: true,
  speakers: true,
  you: true,
  onTranscript: save,
});
const lines = (await live.stop()).turns.map(
  (turn) => `${turn.you ? "You" : `Speaker ${turn.speaker}`}: ${turn.text}`,
);
```

### Notes

`ctx.openNote` opens a note under the notch. While the user points at it or types, it opens up to write in. Otherwise it shrinks to its last two lines, so it stays out of the way during a call. While a live transcription runs, the short note shows the last two lines Voz heard instead, and a warning when Voz can't hear the meeting. It doesn't take the keyboard until the user clicks it. The user can copy it and close it with Esc. Voz shows one note at a time, so a new note replaces the open one.

The note styles Markdown as the user types: `#` headings, `-` and `1.` lists, `- [ ]` checkboxes they can click, `**bold**` and `` `code` ``. Return continues a list. The text stays plain Markdown, so save it as it is.

```ts
voz.startActivity({
  title: "Meeting",
  open(ctx) {
    ctx.openNote({
      title: "Meeting",
      text: notes,
      onChange: (text) => (notes = text),
    });
  },
});
```

- `onChange` gets the full text after the user pauses typing, and when the note closes
- `openNote` returns `{ close() }`. Call it in `ctx`'s handler, such as an activity's `open`, an action or a command

## Ask

`ctx.ask` shows a card under the notch with fields the user can edit and a row of buttons. It waits until the user presses a button or closes the card, so it never acts on a guess. The handler's time stops while the card is open.

```ts
const answer = await ctx.ask({
  title: "Add to calendar?",
  fields: [
    { id: "title", label: "Title", type: "text", value: "Lunch with Tom" },
    { id: "start", label: "Starts", type: "date", value: start },
    {
      id: "calendar",
      label: "Calendar",
      type: "choice",
      value: "Home",
      options: ["Home", "Work"],
    },
  ],
  buttons: ["Copy", "Add"],
});
if (answer?.button === "Add")
  await addEvent(answer.values.title, answer.values.start);
```

- Field types are `text`, `date` (milliseconds since 1970) and `choice` with `options`
- The last button is the main one, and Return presses it
- `answer` is `{ button, values }` with each field's value by `id`, or `null` when the user closes the card with Esc or the close button
- Voz shows one card at a time, so a new card closes the open one, which answers `null`
- A card with only buttons fits one row, like a notification. Give it a `message` under the title and a Lucide `icon`, such as `"audio-lines"`.
- `voz.ask` shows the same card when no handler runs, such as when your extension notices a meeting start. It waits as long as the user takes

## Busy

`ctx.busy(run)` shows a working state in the notch while `run` runs, then a checkmark, or a shake when `run` throws. The user cancels with Esc or the X in the notch. Then `signal` aborts and `busy` resolves `undefined` right away. The handler's time stops while it runs, so a slow model call doesn't time out.

```ts
const reply = await ctx.busy((signal) => fetch(url, { method: "POST", body, signal }).then((response) => response.json()));
if (reply === undefined) return;
```

- Pass `signal` to `fetch` and other calls that take one, so they stop when the user cancels
- Use it instead of `ctx.notify("Working…")`. The notch shows that something runs, and the user can stop it

## Text fields

`ctx.field()` reads the text field that has focus in the front app through Accessibility. Use it with `ctx.select` and `ctx.insert` to rewrite what the user is typing, or to draft a reply to the conversation above the field.

```ts
const field = await ctx.field();
if (!field) return ctx.notify("Click into a text field first");
const { start, length } = field.selection;
const target = length > 0 ? field.text.slice(start, start + length) : field.text;
const rewritten = await rewrite(target, field.before);
if (length === 0 && !(await ctx.select({ start: 0, length: field.text.length }))) ctx.press("cmd+a");
ctx.insert(rewritten);
```

- `field` has `text`, `selection` as `{ start, length }`, `role` such as `AXTextArea`, `label` (the field's description, title or placeholder), and `window`, the window title
- `thread` is the conversation the window shows, as `{ id, title }`. The title is the window title without unread counts or the app name, such as `Anna Schmidt` for `(3) Anna Schmidt - Slack`. It is missing when the title names only the app. Pass `id` to [`voz.history`](#what-the-user-wrote)
- `before` holds up to 6,000 characters of text on screen before the field, such as the messages above a reply box, and `after` up to 1,500 characters after it
- Offsets count UTF-16 code units, the same as JavaScript string indexes
- `field()` returns `null` for password fields, when no text field has focus, and when Voz has no Accessibility permission
- `select(range)` returns `false` when the app ignores it. Fall back to `ctx.press("cmd+a")` to replace the whole field
- `insert` pastes, so it replaces the selection and the user can undo it with Cmd+Z

What Accessibility shows depends on the app:

- Native apps such as Mail, Notes and Messages expose the field and the text around it
- Chromium browsers build their web tree a few seconds after Voz starts or the browser comes to the front. Electron apps such as Slack build it after the first read, so the first `field()` there can return `null`
- Some web editors, such as Google Docs, draw text themselves and expose little or no text
- `before` and `after` read what the app exposes near the field. They can include buttons and labels, and miss text the app keeps off screen

## History

`voz.addHistory` adds an entry to the Voz history, next to dictations. The user can search it, copy it, and open its file in Finder.

```ts
voz.addHistory({
  text: transcript,
  seconds: 3600,
  file: "/Users/me/Meetings/standup.md",
});
```

- `text` is what the history shows, searches and copies
- `seconds` is how long the recording was. It is optional
- `file` is the full path of a file with the same content, such as the Markdown transcript you saved. It is optional
- `copies` lists other parts the user can copy on their own, such as `[{ name: "Notes", text: notes }, { name: "Transcript", text: transcript }]`. Hovering the entry shows a button for each, and right-clicking lists them. It is optional
- Entries from extensions don't count toward Insights
- Entries show a puzzle icon. To pick your own, set a [Lucide](https://lucide.dev/icons) name in `package.json`, such as `{ "voz": { "icon": "file-volume" } }`. Loose files keep the puzzle

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

Settings has a cleanup mode. Both modes run the cleanup model. Heavy uses the prompt and also applies self-corrections, numbers and lists. Light uses a fixed prompt that only removes fillers and fixes punctuation and capitalization. If the model changes any other word, Voz inserts the raw transcript. To keep your words in some apps only, return a mode:

```ts
import { defineExtension } from "voz";

const thinkingApps = ["md.obsidian", "com.apple.Notes"];

export default defineExtension((voz) => {
  voz.on("beforeCleanup", (event, ctx) => {
    if (thinkingApps.includes(ctx.app.bundleID ?? "")) return { mode: "light" };
  });
});
```

A prompt only applies in Heavy mode. If your extension needs its prompt, return `mode: "heavy"` with it, for the apps it handles:

```ts
voz.on("beforeCleanup", (event, ctx) => {
  if (ctx.app.bundleID !== "com.apple.mail") return;
  return {
    prompt:
      event.prompt +
      "\n\nFormat it as an email with a greeting and a sign-off.",
    mode: "heavy",
  };
});
```

## Models and cleanup steps

Voz runs each dictation through a speech model, then through cleanup steps in order. The built-in step is `model`, which uses the cleanup model. Voz ignores the retired steps `fillers`, `punctuation` and `dictionary` in older settings files.

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
- A command has 10 seconds, including the time `ctx.generate` takes. Actions and `recording`, `afterInsert` and `audioDrop` handlers have no time limit, because nothing waits for them
- Each extension has 3 seconds to load. After that, Voz reports it as failed and loads the next one
- If a handler throws or a promise rejects unhandled, Voz logs the error and skips that handler
- `ctx.insert`, `ctx.press` and `ctx.notify` do nothing once a handler has finished or run out of time. Voz logs each dropped call, so `voz dev` shows it. Await your work before the handler returns
- If the extension process exits or stops answering for 2 seconds, Voz restarts it, up to 3 times in a row

## Packages

A package is a folder, git repo or npm package with extensions in it. Voz looks for them in this order:

1. The `voz.extensions` array in `package.json`, such as `{ "voz": { "extensions": ["src/main.ts"] } }`.
2. An `extensions` folder.
3. An `index.ts` or `index.js` file.

Voz does not read `main`. A package with none of these fails to load with an error.

Install and manage packages from the terminal:

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
- See [Versions](#versions) for `"voz": { "apiVersion": 8 }` in `package.json`

## What the user wrote

`voz.history` returns what the user wrote through Voz, newest first, so an extension can write like them or learn from what they kept. It reads two things Voz saves on its own:

- Dictations, with the conversation they went into
- Drafts: text an extension inserted with `ctx.insert`, the text it replaced, and what the user did with it

```ts
const field = await ctx.field();
const examples = await voz.history({ thread: field?.thread?.id, limit: 20 });
const reply = await draft(field.before, examples.map((written) => written.text));
ctx.insert(reply, { instruction: "reply" });
```

- `thread` limits it to one conversation. `source` limits it to drafts one extension inserted, such as `voz.name`. Without `source`, dictations come too. `limit` is 20 unless you set it, and at most 100
- Each item has `kind` (`dictation` or `draft`), `text`, and `at` in milliseconds like `Date.now()`. `text` is what ended up in the field: the user's version when they changed a draft
- Drafts also have `source`, `instruction`, `input` (the text it replaced, empty for a new reply), `output` (what the extension inserted) and `outcome`
- When Voz knows the conversation, items also have `app`, its bundle ID, and `threadTitle`, such as a person or channel
- After an insert, Voz reads the field every second for up to two minutes, until the user leaves the conversation. `outcome` is `kept`, `edited`, `removed`, or `sent` when the field empties while the window stays, as when a chat sends the message. It is `unknown` while Voz watches, and when it can't find the draft in the field
- Edits elsewhere in the field don't count. Text the user types right against the draft does
- `history` is read-only. Extensions can't change or delete what Voz saved, and keep their own data in `voz.paths.data`
- Entries from `voz.addHistory` don't show up here

The user sees the same drafts with `voz drafts`.

## What the user saw

`voz.screen()` reads the text of the window in front, so an extension can learn what the user works on and what a chat said before it scrolled away. Voz reads it only when the extension calls, and keeps none of it. Your extension decides what to store, in `voz.paths.data`, and for how long.

Ask for it in `package.json`. Voz then tells users that your extension reads the screen: in Browse before they install, after `voz install`, with an eye on the Extensions page, and in `voz extensions`:

```json
{ "voz": { "apiVersion": 8, "screen": true } }
```

```ts
setInterval(async () => {
  const screen = await voz.screen();
  if (screen) save(screen);
}, 5_000);
```

- It returns `{ app, window, thread, text }`, or `null` when Voz can't read the window. `thread` is the conversation the window shows, the same `id` as `ctx.field().thread`
- `text` is what the window shows through Accessibility, top to bottom, up to 20,000 characters. Voz never takes screenshots
- Voz skips password fields, password managers, private browser windows and the lock screen, and hides API keys, tokens, private keys, card numbers and IBANs before your extension sees the text
- Without `"screen": true`, `voz.screen()` fails with an error that says so
- Tell users what you keep and how they delete it, and let them turn it off. [voz-reply](https://github.com/Joelheile/voz/tree/main/examples/reply) keeps 30 days in SQLite, has settings to stop or skip apps, and adds `voz reply search` and `voz reply forget`

## Versions

`"voz": { "apiVersion": 8 }` in `package.json` names the oldest Voz API your package needs. Keep it as low as you can, because people run older Voz versions:

- `voz new` writes the current version. The number is also in `voz.d.ts` as `apiVersion`, and `import { apiVersion } from "voz"` gives the version of the Voz that runs
- To use something newer, check for it instead of raising the number. Your package then keeps working everywhere, and gets the new feature where Voz has it:

```ts
if (ctx.ask) {
  const answer = await ctx.ask({
    title: "Add to calendar?",
    buttons: ["Copy", "Add"],
  });
  if (answer?.button !== "Add") return;
}
await addEvent();
```

- Options you pass, such as `at: "anywhere"`, can't be checked that way. Compare the running version instead: `at: apiVersion >= 7 ? "anywhere" : "start"`
- Raise `apiVersion` only when your package can't work without a newer member
- Voz 0.2.0 and older show "Update Voz" instead of loading a package written for a newer API. Newer Voz versions load it, and show "Update Voz" only if loading fails
- A newer Voz runs a package with the API it was written for. API 4 is the last version that changes or removes anything. Later versions only add, so nothing you shipped breaks when Voz updates
- A package without `apiVersion`, and every file in `~/.voz/extensions`, gets the current API plus everything older versions had

What each version changed, and what older packages keep:

| Version | Changes                                                                                                                                                                                                                                                 | Older packages keep                                                         |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 8       | Adds `ctx.field` with `thread`, `ctx.select`, `ctx.busy`, `voz.history`, `instruction` for `ctx.insert`, `model` and `effort` for `ctx.generate`, `ctx.models`, `voz.screen` with `"screen": true` in `package.json`, `voz.generate` with `model: "on-device"`, `voz.registerList`, modifier taps such as `"rightopt"` as hotkeys, and `when` for actions. Adds `you` to `transcribeLive`, `copies` to `addHistory` and `folder` to string settings. Actions take an `icon`, `voz.ask` and `voz.openNote` work outside a handler, `ask` takes a `message` and an `icon`, and a running activity can `stop()` itself. Notes style Markdown and sit under the notch |                                                                             |
| 7       | Adds `ctx.ask` and `at: "anywhere"`                                                                                                                                                                                                                     |                                                                             |
| 6       | Adds `open` to activities, `transcribeLive` on a running activity, `ctx.openNote`, `website` to `ctx.app`, and `voz.registerTool` with `positional`                                                                                                     |                                                                             |
| 5       | Adds `mode` to the `beforeCleanup` event and result                                                                                                                                                                                                     |                                                                             |
| 4       | Adds `voz.startActivity`, `voz.addHistory`, and `hidden` with `update({ hidden })` for actions. `registerCommand` takes one object. `recording` is now `afterRecording`. `ctx` in transform hooks is typed as `{ app }`. Dropped `ctx` calls are logged | `registerCommand(phrase, handler, { at })` and `on("recording")`            |
| 3       | Adds `audioDrop` and `ctx.transcribe`                                                                                                                                                                                                                   |                                                                             |
| 2       | Adds `at: "start"` and `ctx.generate`. Removes `voz.config`, `voz.log`, `voz.events`, `voz.paths.home` and `{ handled: true }` from `beforeInsert`                                                                                                      | All of them. New code uses `voz.settings`, `console.log` and `{ text: "" }` |

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
  "cleanupSteps": ["model", "voz-jira/jira"]
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

Installing a package does not run its code, because Voz never runs install scripts. Voz installs exact versions and changes a package only when you run `voz update`.
