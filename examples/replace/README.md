# voz-replace

Fix words Voz writes the way you don't, and turn short phrases into longer text.

- "air pods" becomes "AirPods"
- "raycast, reycast, recast" all become "Raycast"
- "gonna" becomes "going to", and "Going to" at the start of a sentence
- Say "my email" and Voz types your address. A dictation that is only the shortcut gives just the text, without a period
- Leave the replacement empty to delete words, such as "basically"

```
voz install voz-replace
```

Add a replacement with Add replacement on Replace's page under Extensions, or in the terminal:

```
voz replace add "air pods, airpods" AirPods
voz replace add "my signature" "Best,\nLeonard"
voz replace add basically
voz replace test "basically my air pods died"
voz replace list
voz replace remove basically
```

Spellings match whole words, ignore case, and don't care how many spaces sit between words. Write `\n` for a new line. For patterns, write a regular expression between slashes: `/ticket (\d+)/` with `VOZ-$1` turns "ticket 42" into "VOZ-42". It ignores case unless you add flags, such as `/IT/g`.

Replace runs after cleanup, on the text Voz types, so the model can't change a replacement back. Your rules are in `~/.voz/data/voz-replace/rules.json`. Voz's Dictionary also fixes misheard names, and helps the speech model hear them. Use Replace for everything else.
