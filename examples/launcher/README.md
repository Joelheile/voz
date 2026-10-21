# voz-launcher

Start a dictation with "computer" and Voz runs it instead of typing it.

- "Computer, open Safari" opens Safari
- "Computer, search for flights to Lisbon" opens a web search
- "Computer, run deploy" runs the `deploy` command from your settings

```
voz install voz-launcher
```

Change the trigger word and search engine in the Extensions page. Add commands in `~/.voz/settings.json`. Each key is the name you say, each value is a shell command:

```json
{
  "config": {
    "voz-launcher": {
      "deploy": "cd ~/site && npm run deploy"
    }
  }
}
```

Only the commands you add here run. Voz never runs other spoken text as a shell command.
