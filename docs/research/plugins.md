# Plugin research

Date: 2026-10-17. Question: can voz follow pi's model, a small core that users extend with installable packages? What would voz need to build?

Sources are cited by number. See the list at the end.

## Answer

Yes, with one change to pi's model. pi loads TypeScript extensions into its own Node process and trusts them fully [1][2]. voz is a signed native app with a 1.5 s latency budget and a privacy promise. A crashing or slow plugin inside the voz process breaks dictation for everyone. So voz plugins run out of process, or as data that voz reads.

Build it in three tiers. Ship tier 1 and tier 2 first. Add tier 3 only when a real plugin needs it.

| Tier       | What a package contains             | Runs where                                   | Covers                                                                       |
| ---------- | ----------------------------------- | -------------------------------------------- | ---------------------------------------------------------------------------- |
| 1. Data    | JSON and Markdown files             | voz reads them                               | Dictionary words, replacements, cleanup modes, per-app rules, sounds, themes |
| 2. Hooks   | An executable plus a manifest entry | Child process, JSON over stdin and stdout    | Transform text, send text somewhere, voice commands                          |
| 3. Scripts | JavaScript                          | JavaScriptCore VM inside voz, host APIs only | UI contributions and stateful plugins, if tier 2 is not enough               |

## What pi does

- The core is small: four tools and a system prompt under 1,000 tokens. Everything else is an extension [4][5].
- An extension is a TypeScript file with a default export that receives an `ExtensionAPI`. It subscribes to events with `pi.on()` and registers tools, commands, shortcuts and flags [2].
- A package bundles extensions, skills, prompts and themes. pi finds them in conventional folders or in a `pi` key in `package.json` [3].
- `pi install` takes `npm:`, `git:` or a local path. Git tags stay pinned. `pi list`, `pi remove`, `pi update` and `pi config` manage installs [3].
- Settings hold the package list, globally or per project. Filters with globs choose which resources load [3].
- The gallery at pi.dev lists npm packages that carry the `pi-package` keyword [3][6].
- Security is a warning: packages run code, review the source first [3][6].

## How other apps do it

| App               | Plugin format                                                        | Isolation                                                           | Distribution                                    |
| ----------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------- | ----------------------------------------------- |
| VS Code [7][8]    | `package.json` with static `contributes` and `activationEvents`      | Separate extension host process                                     | Marketplace                                     |
| Raycast [9][10]   | React and TypeScript, custom reconciler renders native AppKit views  | One child Node process, one V8 isolate per extension, fixed RPC API | Store with review                               |
| Zed [11]          | `extension.toml` plus Rust compiled to WASI                          | WebAssembly sandbox                                                 | Git repo, central index                         |
| Obsidian [12][13] | `manifest.json` plus `main.js` from a GitHub release                 | None, same Electron process                                         | Automated review, community list                |
| Espanso [14]      | `_manifest.yml` plus `package.yml` of snippets, no code              | Data only                                                           | Hub is a GitHub repo, PR to publish             |
| Hammerspoon [15]  | `.spoon` folder with Lua                                             | Same process                                                        | Zip files in a GitHub repo, SpoonInstall        |
| Talon [16]        | `.talon` files map speech to actions, Python implements them         | Same process                                                        | Clone `talonhub/community` into the user folder |
| Claude Code [17]  | `plugin.json` with commands, hooks, skills                           | Hooks are child processes                                           | `marketplace.json` in any git repo              |
| superwhisper [18] | Modes: a speech model, a language model and a prompt, stored as JSON | Data only                                                           | None, local files                               |

Patterns that repeat:

- A manifest declares what a package adds before any code runs (VS Code, Zed, Obsidian, Claude Code, pi).
- A git repo is enough for a registry (Espanso, Hammerspoon, Zed, Claude Code). An index file or a GitHub topic is enough for a gallery.
- Apps that run plugins in process have no real security story (Obsidian, Hammerspoon). Apps that care isolate them (VS Code, Raycast, Zed).
- The closest voice products, Talon and superwhisper, get most of their value from data: command files and prompt modes.

## Constraints specific to voz

- **Native code plugins are a bad fit.** voz already sets `com.apple.security.cs.disable-library-validation`, so it could `dlopen` third-party dylibs. Apple advises against this, Gatekeeper checks such apps harder, and an in-process plugin can crash the app [19]. Do not load third-party Swift or dylibs.
- **ExtensionKit is not ready for this.** macOS 26 adds `AppExtensionPoint`, which lets a host app declare extension points. Third-party scope is documented thinly and a forum report shows errors [20]. Each plugin would also need Xcode and signing, which raises the bar for authors.
- **JavaScriptCore is built in.** It needs no dependency. A `JSContext` exposes only the functions voz registers. Each plugin can get its own `JSVirtualMachine` [21]. This makes tier 3 cheap when it is needed.
- **WebAssembly needs a runtime.** Extism has no Swift SDK [22]. Wasmtime through C works but adds a large dependency. Skip for now.
- **voz is not sandboxed.** It can start child processes, so tier 2 needs no entitlement change.
- **Latency.** Key release to text targets 1.5 s (`speed.md`). A hook gets a hard timeout. On timeout or error, voz delivers the text it had and logs the failure.
- **Privacy.** The README says transcripts stay on the Mac. A plugin that sees transcripts can send them anywhere. The install prompt must say so.

## What to build

In order. Each step ships on its own and leaves dictation working.

### 1. Pipeline seam

`DictationPipeline.run` goes straight from `session.finish` to `output.deliver`. Add one stage between them: a list of text transforms, each `(String, Context) async -> String`. The built-in cleaner stays where it is. With an empty list, behavior does not change.

Context passed to every hook: raw text, cleaned text, front app bundle ID and name, language mode, audio seconds.

### 2. Package format and loader

A package is a folder with `voz.json`:

```json
{
  "name": "jira-keys",
  "version": "1.0.0",
  "description": "Spoken ticket numbers become JIRA-123",
  "dictionary": ["dictionary.txt"],
  "replacements": ["replacements.json"],
  "modes": ["modes/*.md"],
  "hooks": [
    {
      "event": "transform",
      "command": "bin/transform",
      "apps": ["com.atlassian.*"],
      "timeoutMs": 300
    }
  ]
}
```

- Packages live in `~/Library/Application Support/voz/packages/<name>`.
- A user folder at `~/Library/Application Support/voz/extensions` loads loose files with no manifest, like pi's `extensions/` folder [2].
- Settings store the installed list with source and pinned commit, plus an enabled flag per package.

### 3. Data resources (tier 1)

Wire each resource type into code that exists today:

| Resource          | Feeds                                                                      |
| ----------------- | -------------------------------------------------------------------------- |
| `dictionary`      | `VocabularyStore`, as read-only words tagged with the package name         |
| `replacements`    | A rule pass next to `SpokenPunctuation` and `VocabularyCasing`             |
| `modes`           | Cleanup instructions per app or per shortcut, like superwhisper modes [18] |
| `sounds`, `theme` | `SoundCues` and `Theme`                                                    |

### 4. Hook runner (tier 2)

- Start the command with `Process`. Write the context as JSON to stdin. Read `{ "text": "..." }` from stdout.
- Kill the process at `timeoutMs`. Use the existing `withTimeout` in `Cleanup/Timeout.swift`.
- Events to start with: `transform` (can change text) and `delivered` (fire and forget, for sending text to Notes, a webhook or a log).
- Later events: `command` (a spoken phrase such as "send it" runs a hook instead of inserting text), `recording.start`, `recording.stop`.

### 5. Install command

Extend the headless argument parsing in `Headless.swift`:

```
voz install git:github.com/user/voz-jira-keys@v1.0.0
voz install ./my-package
voz list
voz remove jira-keys
voz update
```

- Git only at first. Clone with `--depth 1`, pin the commit, never run install scripts. pi's README makes the same point about npm lifecycle scripts [1].
- Before enabling, show what the package adds: words, modes, hooks, and the line "This package runs code on your Mac and can read your transcripts" if it has hooks.

### 6. Settings UI

A Packages section in `SettingsView`: installed list, enable toggle, remove, update, and an "Open folder" button for local development.

### 7. Docs, examples and gallery

- `docs/plugins.md` with the manifest schema and the hook protocol.
- Two or three example packages in their own repo: a replacements pack, a hook that formats text for Slack, a hook that appends to a daily note.
- Gallery: a GitHub topic such as `voz-package`, then a small index page. Same approach as pi's `pi-package` keyword [3].

### Later, only on demand

- Tier 3 JavaScriptCore runtime with a typed API that mirrors the hook events.
- Plugin-provided speech engines. These would run as a child process that streams audio. Hard to fit in the latency budget.
- Analytics: count installs per package name, never package contents.

## Open questions

- Should cleanup modes replace the single cleanup prompt, or add to it?
- Is a hook allowed to cancel insertion, for example for a voice command?
- Per-app rules: match on bundle ID only, or also on window title as Talon does [16]?

## Sources

1. pi coding agent README. https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/README.md
2. pi extensions docs. https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/extensions.md
3. pi packages docs. https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/packages.md
4. Mario Zechner, "What I learned building an opinionated and minimal coding agent" (republished). https://conffab.com/elsewhere/what-i-learned-building-an-opinionated-and-minimal-coding-agent/
5. pi.dev deep dive. https://urandom.io/blog/2026-03-07-pi-dev-deep-dive
6. pi.dev package registry. https://pi.dev/packages/@lnittman/pi-tools
7. VS Code, "Our approach to extensibility". https://vscode-docs1.readthedocs.io/en/stable/extensions/our-approach/
8. VS Code contribution points. https://code.visualstudio.com/api/references/contribution-points
9. Raycast, "How the Raycast API and extensions work". https://raycast.com/blog/how-raycast-api-extensions-work
10. Raycast developer docs, security. https://developers.raycast.com/information/security
11. Zed, developing extensions. https://zed.dev/docs/extensions/developing-extensions.html
12. Obsidian, submit your plugin. https://docs.obsidian.md/Plugins/Releasing/Submit+your+plugin
13. Obsidian forum, security of plugins. https://forum.obsidian.md/t/security-of-the-plugins/7544
14. Espanso package specification. https://espanso.org/docs/packages/package-specification/
15. Hammerspoon SpoonInstall. https://www.hammerspoon.org/Spoons/SpoonInstall.html
16. Talon docs. https://talonvoice.com/docs/
17. Claude Code plugins and marketplaces guide. https://www.morphllm.com/claude-code-marketplace
18. superwhisper custom modes. https://superwhisper.com/docs/modes/custom
19. Apple, disable library validation entitlement. https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation
20. Apple, AppExtensionPoint, and forum thread 805437. https://developer.apple.com/documentation/extensionfoundation/appextensionpoint and https://developer.apple.com/forums/thread/805437
21. Kodeco, JavaScriptCore tutorial. https://www.kodeco.com/1227-javascriptcore-tutorial-for-ios-getting-started
22. Extism. https://extism.org
