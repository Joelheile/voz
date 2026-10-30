import { defineExtension } from "voz";

export default defineExtension((voz) => {
  const { key } = voz.settings({
    key: { type: "string", title: "Key", default: "return", options: ["return", "cmd+return", "shift+return"] },
  });

  voz.registerCommand({ phrase: "send it", run: (event, ctx) => ctx.press(key) });
});
