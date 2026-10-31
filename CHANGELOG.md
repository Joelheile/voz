# What's new in Voz

Newest first. To get beta changes now, turn on Beta updates under What's new in Settings.

## 0.1.0 (October 31, 2026)

- Extension entries in your history show the icon their package picks
- Settings groups are easier to scan, with Live preview under While recording
- A broken extension package no longer stops your other extensions from loading
- With Reduce Motion on, the indicator stops shaking and icons fade in
- Choose which microphone Voz records from in Settings
- Drop audio files on the notch again, with a glow showing where they go
- Pick Light cleanup to keep every word when you think out loud
- Voz sends one anonymous ping on days you dictate, never what you said
- Hover the progress ring to cancel a file transcription
- Your last word no longer gets cut off when you release the hotkey early
- Find settings faster, with release notes one click away at the top
- Open your dictionary straight from the main panel
- Quit Voz from the bottom of Settings
- See how many times faster than typing you speak in Insights
- Claude Code reads the Voz extension guide when you build an extension
- Copy a debug log from Privacy in Settings to report problems
- See extension recordings in the menu bar and stop them from the panel
- Extension actions can now record or transcribe for as long as they need
- Extensions can add entries, such as meeting transcripts, to your Voz history
- Transcripts from extensions use your dictionary and show progress in the notch
- On screens without a notch, the recording pill now sits above the Dock
- Drop an audio or video file on the indicator to transcribe it
- Track your dictation streak, speaking pace and time saved in Insights
- Fix words Voz keeps mishearing with dictionary rules, like voss → Voz
- Preview your words under the indicator while you speak. See Live preview in Settings
- Text appears sooner after you stop, and the first dictation after launch is faster
- A cleaner panel that opens and switches pages instantly
- The dictionary learns words from names you spell out and corrections you say
- Find, add and accept dictionary words from one field
- Cleanup now fixes whole sentences across pauses
- The hotkey records on the first press after wake or a microphone switch
- Voz no longer freezes when your microphone changes, like when AirPods disconnect
- Voz tells you when it can't start recording
- Voz starts faster after an install or update
- Updates arrive within an hour of release
- Crash reports are on, never with text or audio. Turn them off in Privacy
- Extensions get a simpler list, with a page that shows what each one does
- Run extension actions from buttons at the bottom of the panel
- Turn on an extension's cleanup steps from its page
- Copy a Claude Code prompt from the Extensions page to build your own extension
- Extensions can use the on-device model and handle commands you say first
- Extensions written for the first extension API, such as voz-autocorrect and voz-meeting, load again
- Extensions that miss their deadline can no longer change your text
- `ctx.generate` gives a clear error when a required field doesn't exist
- Long notifications show in full
- The Voz face is back in the menu bar, turning white on dark bars
- Small bars in Top apps stay visible
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
