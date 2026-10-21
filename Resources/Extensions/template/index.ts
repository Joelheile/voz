import { defineExtension } from "voz";

export default defineExtension((voz) => {
  const settings = voz.settings({
    greeting: { type: "string", title: "Greeting", default: "Hello from {{name}}" },
  });

  voz.registerCommand("say hello", (event, ctx) => ctx.notify(settings.greeting));
});
