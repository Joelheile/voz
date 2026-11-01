import { defineExtension } from "voz";

export default defineExtension((voz) => {
  const settings = voz.settings({
    greeting: { type: "string", title: "Greeting", default: "Hello from {{name}}" },
  });

  voz.registerCommand({ phrase: "say hello", run: (event, ctx) => ctx.notify(settings.greeting) });

  voz.registerTool({
    id: "greet",
    description: "Show the greeting. Run it as voz {{name}} greet Ada",
    input: { type: "object", properties: { who: { type: "string", description: "Who to greet" } } },
    positional: ["who"],
    run: (input, ctx) => {
      ctx.notify(`${settings.greeting}, ${input.who ?? "you"}`);
      return { greeted: input.who ?? "you" };
    },
  });
});
