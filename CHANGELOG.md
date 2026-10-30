# What's new in Voz

Newest first. To get beta changes now, turn on Beta updates under What's new in Settings.

## In beta

- Pick Light cleanup to keep every word when you think out loud
- Voz sends one anonymous ping on days you dictate, never what you said
- Transcribe dropped files about four times faster, and hover the progress ring to cancel
- Your last word no longer gets cut off when you release the hotkey early
- Find settings faster, with release notes one click away at the top
- Open your dictionary straight from the main panel
- Quit Voz from the bottom of Settings
- See how many times faster than typing you speak, on a pace gauge in Insights
- See your word, streak and time-saved milestones right in the panel
- Claude Code now reads the Voz extension guide when you build an extension in ~/.voz
- Copy a debug log from Privacy in Settings to report problems or debug an extension
- Extensions can show a recording in the menu bar and let you stop it from the Voz panel
- Extension actions can now record or transcribe for as long as they need
- Extensions can add entries, such as meeting transcripts, to your Voz history
- Transcripts from extensions use your dictionary and show progress in the notch
- On screens without a notch, the recording pill now sits above the Dock
- Drop an audio or video file on the indicator to transcribe it with an extension
- Track your dictation streak, speaking pace and time saved in Insights
- Fix words Voz keeps mishearing with dictionary rules, like voss → Voz
- Preview your words below the recording indicator while you speak. Turn on Live preview in Settings
- Text appears sooner after you stop talking, and the first dictation after launch transcribes faster
- A cleaner panel that opens and switches pages instantly
- The dictionary learns words from names you spell out and corrections you say
- Find, add and accept dictionary words from one field
- Cleanup now fixes whole sentences across pauses
- The hotkey starts recording on the first press after your Mac wakes or switches microphones
- Voz no longer freezes when your microphone changes, like when AirPods disconnect
- Voz tells you when it can't start recording
- Voz starts faster after an install or update
- Updates arrive within an hour of release
- Crash and freeze reports are on by default, with their own switch under Privacy. They never include text or audio
- Extensions get a simpler list, with a page for each one that shows what it does
- Run extension actions from buttons at the bottom of the panel
- Turn on an extension's cleanup steps from its page
- Copy a Claude Code prompt from the Extensions page to build your own extension
- Extensions can use the on-device model and run commands you say at the start of a dictation
- Extensions written for the first extension API, such as voz-autocorrect and voz-meeting, load again
- Extensions that miss their deadline can no longer change your text
- `ctx.generate` gives a clear error when a required field doesn't exist
- Long notifications show in full
- The Voz face is back in the menu bar, and it turns white on dark menu bars
- Small bars in Top apps stay visible
- Dragging a TypeScript file no longer opens the drop zone
- When you reach a word, streak or time-saved milestone, the panel shows it once

## 0.0.5 (October 22, 2026)

- See the time left while a speech model downloads
- See your top apps, with their icons, in Insights
- Copy, paste, select all and undo work in the Voz panel
- Drag Voz from a tile next to System Settings into Accessibility and Input Monitoring
- Installing the `voz` command asks for your password instead of handing you a Terminal command
- Voz tells you when its menu bar icon hides behind the notch
- Voz tells you when microphone access is denied
- Calmer settings, and a red dot while you record
- Smoother transcript navigation and matching menu icons
- Slow extensions and cleanup can no longer stall dictation or startup
- Updates install only while your Mac is idle
- Setup runs again after a fresh install
- Moving Voz to the Trash quits it and removes its login item
- Paste one prompt into a coding agent to build an extension
- A simpler extension API: read settings with `voz.settings`, log with `console.log`, and return `{ text: "" }` to insert nothing
- Voz includes the licenses of the open source code it uses

## 0.0.1 (October 19, 2026)

- The first release. Tap right Command, talk, and Voz types clean text into any app
