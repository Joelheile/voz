# voz-reply

Draft a reply that sounds like you. Click into the reply box of a chat or email and tap right Option.

```
voz install voz-reply
```

Add your name as it shows in chats on the Extensions page, so Voz can find your own messages.

- **Right Option:** with the field empty, it writes the most likely reply. With notes typed, such as "yes but next week", it writes them out in your tone. With a message started, it fixes and finishes it.
- **Say "reply …":** such as "reply sounds good, I'll bring the slides".

Reply copies how you write in that conversation: length, capitalization, greetings and emoji. It never makes up details, and leaves a placeholder such as [time] instead.

Reply also learns how you write in each app, and with some people. When you change a reply before you send it, delete it, or tap for a different one, Apple's model on your Mac turns that into a short rule, such as "no greeting, all lowercase". Every few hours it also reads what you sent in each app. This runs on your Mac and costs nothing, even when ChatGPT or Claude writes your replies. They get the rules with each reply. See and delete the rules under "Writing style" on Reply's page in Settings, or run `voz reply style` and `voz reply forget-style <words>`. Learning needs Apple Intelligence.

Tap right Option again while the reply is still in the field, and Reply writes a different one.

Reply reads your screen, so it knows what you have been working on and what the chat said before it scrolled away. Every 5 seconds it reads the text of the window in front and keeps it in `~/.voz/data/voz-reply` for 30 days. Voz hides passwords and keys before Reply sees the text, and skips password managers and private browser windows. Search it with `voz reply search <words>`, and delete it with `voz reply forget`. To leave out apps, list them under "Never remember" in Reply's settings. To stop it, turn off "Remember the screen": Reply then reads only the window you reply in, when you reply.

The notch shows that Voz is writing. Press Esc or click the X to stop. The field stays as it is until the reply is ready. If you type in the meantime, the reply opens in a note instead. Press Cmd+Z to undo.

The first time you tap right Option, Voz asks which AI should write: ChatGPT, a Claude API key or Apple's model, which runs on your Mac and is free. ChatGPT and Claude write replies that sound more like you. With them, Voz sends the text on screen around the field, and the parts of what it saw on screen that match the conversation, to OpenAI or Anthropic only when you reply. It reads it through Accessibility, so it works in native apps, browsers and Slack. Password fields are never read.
