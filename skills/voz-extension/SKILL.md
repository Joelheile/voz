---
name: voz-extension
description: Builds, changes and debugs Voz extensions, the TypeScript plugins for the Voz dictation app on the Mac. Use when the user wants Voz to do something new with what they dictate, such as a voice command, a writing style per app, a hotkey or a tool agents can call, or works in a `voz new` folder or `~/.voz/extensions`, or when a Voz extension fails to load.
---

# Voz extension

Voz is a Mac dictation app. It records, transcribes, cleans up and types text. An extension is TypeScript that Voz runs with Bun to change what happens with a dictation, or to add commands. Your job is to turn what bothers the user into the smallest extension that fixes it, and to prove it works in a real dictation.

Copy this checklist into your reply and keep it current:

```
- [ ] 1. Look: Voz's current state is known
- [ ] 2. Interview: the user said yes to a one-sentence spec
- [ ] 3. Pick: each part of the spec maps to an API member
- [ ] 4. Build: the smallest version exists
- [ ] 5. Verify: tests pass, it loads clean, the user confirmed a real dictation
- [ ] 6. Hand over
```

The API is in [references/api.md](references/api.md). Read the section for each member you use before you write code that calls it.

## 1. Look

Finding facts is your job, never the user's. Run these before you ask anything:

- `voz status`: permissions, speech model and loaded extensions. Exit code 3 means Voz is closed: run `voz start`
- `voz extensions`: what is installed, whether it loaded, its error and settings
- `voz history --limit 5`: what the user really dictates
- `voz help`: every command. `voz help <words>` finds one

If `voz` is not on the PATH, use `/Applications/voz.app/Contents/MacOS/voz`.

Done when you know what is installed, what is broken, and whether an installed extension already does part of the idea.

## 2. Interview

Interview the user until you both picture the same extension. Ask one question at a time, in plain words, with two to four options and your recommended answer first. Skip what the user already told you, and look up facts yourself, such as a bundle ID with `osascript -e 'id of app "Slack"'`.

Find out:

1. What starts it: a phrase, every dictation, an app, a button or a hotkey
2. What it does: changes the text, or acts somewhere else
3. Two or three things the user would say, and the exact result for each. These become your tests
4. What the user sets up, such as a token. Each one is a setting
5. Whether it stays private or gets shared on npm

Done when you can say the extension in one sentence and the user says yes. Write no code before that.

## 3. Pick

| The user wants                                                    | Use                                                             |
| ----------------------------------------------------------------- | --------------------------------------------------------------- |
| A phrase that does something, such as "send it"                   | `registerCommand`                                               |
| A dictation that becomes data, such as "todo call Milan tomorrow" | `registerCommand` with `at: "start"` and `ctx.generate`         |
| A different writing style in some apps or sites                   | `beforeCleanup`, adding to `event.prompt`                       |
| Fewer changes in some apps, such as notes                         | `beforeCleanup` returning `{ mode: "light" }`                   |
| A fixed text rule, such as a regex                                | `registerCleanupStep`                                           |
| The final say over what gets typed                                | `beforeInsert`                                                  |
| Dictations saved or sent somewhere after they are typed           | `afterInsert`                                                   |
| The audio, or files dropped on the notch                          | `afterRecording`, `audioDrop` with `ctx.transcribe`             |
| Another speech or cleanup model                                   | `registerSpeechModel`, `registerCleanupModel`                   |
| A button in the Voz panel, or a global hotkey                     | `registerAction`                                                |
| Something agents and the terminal can run                         | `registerTool`                                                  |
| Something that keeps running, such as a meeting recording         | `startActivity`, `transcribeLive`, `ctx.openNote`, `addHistory` |
| A check before acting                                             | `ctx.ask`                                                       |
| Rewriting or replying to what the user is typing                  | `ctx.field`, `ctx.select`, `ctx.busy`                           |
| Writing like the user, or learning from what they changed         | `voz.history`, `voz.generate`                                   |
| What the extension learned, so the user can remove it             | `registerList`                                                  |
| What the user works on, and chats that scrolled away              | `voz.screen`                                                    |

`beforeCleanup`, `beforeInsert` and cleanup steps get 300 ms and only `ctx.app`: string work only. Put network and model calls in commands, actions, tools or `afterInsert`. See Limits in [references/api.md](references/api.md).

## 4. Build

- **Private**: write one file, such as `~/.voz/extensions/slack-send.ts`. Voz loads it on save. Types are in `~/.voz/node_modules/voz/index.d.ts`. A loose file can't import npm packages: for one, make a folder with `package.json` and `index.ts`, then `voz install ./that-folder`
- **To share**: run `voz new voz-<name>` in the user's code folder, then `voz dev voz-<name>` in the background, since it keeps running. It reloads on save, prints logs and writes the types to `voz.d.ts`

Put the logic that decides things in plain functions with `bun test` tests, and keep the default export thin: it registers handlers and has 3 seconds to finish.

Rules the types don't tell you:

- Append to `event.prompt` in `beforeCleanup`, so the user's own cleanup prompt keeps working
- Make every value the user may change a setting with `voz.settings`. Fill settings with `voz config <name> <key> <value>`, and pass `-` to read a token from stdin
- Await your work before a handler returns. `ctx` calls after that do nothing
- Write files to `voz.paths.data`. A write next to the code reloads the extension
- Let the user turn the extension on and off in Voz, with its switch or `voz disable <name>`
- Throw an `Error` whose message says what to run next. Fix causes instead of catching errors silently or inventing fallback values
- Send transcripts only where the user asked
- In a package, keep `apiVersion` in `package.json` as `voz new` wrote it, and check for newer members with `if (ctx.ask)`

## 5. Verify

1. `bun test` passes with the user's examples. If `bun` is missing, use `~/Library/Application Support/voz/bun/<version>/bun`
2. `voz extensions` shows it loaded with no error, and `voz logs --extensions --since 5m` shows no errors
3. Each tool and action runs: `voz <name> <id> --help`, then `voz <name> <id>`
4. The user dictates each example and tells you what Voz typed or did

When a step fails, fix the cause and run every step again. Done when all four pass in one run.

## 6. Hand over

Show the commands you ran and their output. Then tell the user the sentence to dictate, which settings to fill in under Extensions in the Voz panel, and how to turn it off. For a package, they publish with `npm publish`: the `voz-package` keyword lists it in the Extensions page, and others install it with `voz install <name>`.
