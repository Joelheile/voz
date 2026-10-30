import { defineExtension } from "voz";

export default defineExtension((voz) => {
  const settings = voz.settings({
    greeting: { type: "string", title: "Greeting", default: "Hello from {{name}}" },
  });

  voz.registerCommand({ phrase: "say hello", run: (event, ctx) => ctx.notify(settings.greeting) });
});
