import { defineExtension } from "voz";

const reserved = new Set(["trigger", "searchURL"]);

export default defineExtension((voz) => {
  const trigger = String(voz.config.trigger ?? "computer").toLowerCase();
  const searchURL = String(voz.config.searchURL ?? "https://www.google.com/search?q=");
  const pattern = new RegExp(`^${trigger},?\\s+(open|search for|run)\\s+(.+?)[.!?]*$`, "i");

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
      case "run": {
        const name = target.toLowerCase();
        const command = voz.config[name];
        if (reserved.has(name) || typeof command !== "string") {
          ctx.notify(`No command named ${target}`);
          break;
        }
        spawn(["/bin/zsh", "-lc", command], ctx, `${target} failed`);
        ctx.notify(`Running ${target}`);
        break;
      }
    }
    return { handled: true };
  });
});
