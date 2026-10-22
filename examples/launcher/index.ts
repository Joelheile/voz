import { defineExtension } from "voz";

export default defineExtension((voz) => {
  const { trigger, searchURL } = voz.settings({
    trigger: { type: "string", title: "Trigger word", description: "Start a dictation with it to run it", default: "computer" },
    searchURL: { type: "string", title: "Search URL", default: "https://www.google.com/search?q=" },
  });
  const pattern = new RegExp(`^${trigger.toLowerCase()},?\\s+(open|search for)\\s+(.+?)[.!?]*$`, "i");

  const spawn = (command: string[], ctx: { notify(text: string): void }, failure: string) =>
    Bun.spawn(command).exited.then((code) => code !== 0 && ctx.notify(failure));

  voz.on("beforeInsert", (event, ctx) => {
    const match = event.text.trim().match(pattern);
    if (!match) return;
    const [, verb, target] = match;
    switch (verb.toLowerCase()) {
      case "open":
        spawn(["open", "-a", target], ctx, `No app named ${target}`);
        break;
      case "search for":
        spawn(["open", searchURL + encodeURIComponent(target)], ctx, "Search failed");
        break;
    }
    return { text: "" };
  });
});
