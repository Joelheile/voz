# What's new in Voz

Newest first. To get beta changes now, turn on Beta updates under What's new in Settings.

## In beta

- Take notes under the notch and copy notes or the transcript from history
- See the live transcript and elapsed time in the notch during a meeting
- Pick ChatGPT or Claude under Settings > AI model for better writing
- Tap right Option in a chat and Reply drafts your answer in your voice
- Select text and tap right Option to tell Edit how to change it
- See which extensions read your screen before you install them
- Reply learns how you write in each app and lists it in Settings
- Download Voz as a disk image and open it without a security warning
- The star card shows how many words you've dictated with Voz
- Cancel a speech model download from the menu bar
- Dictated text now pastes into slow apps instead of your old clipboard
- See your streak, today's words and time saved first in Insights
- Insights now comes first in the menu footer
- Search history by words in any order, app name, today or yesterday, even with typos
- Extension pages show what each one does first, with downloads and last update below
- Click Build your own in Extensions, and any coding agent builds one with you
- Build your own sets up the extension skill for Claude Code and Codex in every project
- The menu bar panel has a cleaner look, with grouped settings and clear status
- Updates install on their own while you're away from your Mac
- Opening Voz from the disk image moves it to Applications and ejects the image
- Voz no longer freezes for a few seconds when you switch to a Chrome window
- Dictation records from your default microphone when the one you picked won't start
- Text appears sooner after you let go of the hotkey
- Extensions can ask you to check details in a card under the notch
- Extensions made for a newer Voz now load instead of asking you to update
- Extension commands can now trigger on a phrase said anywhere in your dictation
- Dictation starts while music plays, during meetings and with Bluetooth headphones
- Opening Voz after an update no longer leaves an invisible old copy running
- When an update is ready, Update appears at the bottom of the menu
- In Hold mode, tap the hotkey to dictate hands-free or hold it to talk

## 0.2.0 (November 2, 2026)

- Send feedback from Settings or with voz feedback, typed or dictated
- After a few dictations, Voz asks once if you'd star it on GitHub
- Control Voz from the terminal: run voz help to see every command
- Connect Claude, Codex and other AI apps to Voz with voz mcp
- Print a dictation in the terminal with voz dictation stop --print
- Extensions can take live notes while you talk, in a panel by the notch
- Take a short tour of what Voz can do after setup
- Pick the languages you speak in Settings so dictation stops mixing alphabets
- Cleanup keeps your words in the language you spoke them
- The notch opens and closes more smoothly
- Typing in other apps keeps working when Voz opens its panel at launch
- Voz no longer freezes after your microphone or headphones change
- Your Voz icon no longer hides behind the notch when your menu bar is full

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
