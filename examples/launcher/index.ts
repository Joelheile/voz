import { defineExtension } from "voz";

export default defineExtension((voz) => {
  const { trigger, searchURL } = voz.settings({
    trigger: { type: "string", title: "Trigger word", description: "Start a dictation with it to run it", default: "computer" },
    searchURL: { type: "string", title: "Search URL", default: "https://www.google.com/search?q=" },
  });
  const pattern = /^(open|search for)\s+(.+?)[.!?]*$/i;

  voz.registerCommand({
    phrase: trigger,
    at: "start",
    async run(event, ctx) {
      const match = event.text.match(pattern);
      if (!match) return ctx.notify(`Say "${trigger}, open" or "${trigger}, search for"`);
      const [, verb, target] = match;
      const isOpen = verb.toLowerCase() === "open";
      const code = await Bun.spawn(isOpen ? ["open", "-a", target] : ["open", searchURL + encodeURIComponent(target)]).exited;
      if (code !== 0) ctx.notify(isOpen ? `No app named ${target}` : "Search failed");
    },
  });
});
