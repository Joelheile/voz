import { mkdirSync } from "node:fs";
import { defineExtension } from "voz";
import { describe, RuleStore } from "./rules";

export default defineExtension((voz) => {
  mkdirSync(voz.paths.data, { recursive: true });
  const rules = new RuleStore(`${voz.paths.data}/rules.json`);

  // After cleanup, so the model can't undo a replacement, and only on the text Voz types
  voz.on("beforeInsert", (event) => ({ text: rules.apply(event.text) }));

  voz.registerList({
    id: "rules",
    title: "Replacements",
    description: "Add one with the Add replacement action, or voz replace add",
    items: () => rules.all().map((rule) => ({ id: rule.from, title: describe(rule) })),
    remove: (from) => void rules.remove(from),
  });

  voz.registerAction({
    id: "add",
    name: "Add replacement",
    icon: "replace",
    hidden: true,
    async run(ctx) {
      const answer = await ctx.ask({
        title: "Add a replacement",
        message: "Separate spellings with commas. Leave With empty to delete them.",
        icon: "replace",
        fields: [
          { id: "from", label: "Replace", type: "text", value: "" },
          { id: "to", label: "With", type: "text", value: "" },
        ],
        buttons: ["Cancel", "Add"],
      });
      if (answer?.button !== "Add") return;
      const rule = { from: String(answer.values.from ?? ""), to: String(answer.values.to ?? "") };
      try {
        rules.add(rule);
        ctx.notify(`Added ${describe(rule)}`);
      } catch (error) {
        ctx.notify((error as Error).message);
      }
    },
  });

  voz.registerTool({
    id: "list",
    description: "List your replacements and snippets",
    readOnly: true,
    run: () => rules.all(),
  });

  voz.registerTool({
    id: "add",
    description: "Add a replacement, or change the one with the same spellings. Repeating it changes nothing",
    input: {
      type: "object",
      properties: {
        from: {
          type: "string",
          description: 'Spellings to replace, separated by commas, such as "air pods, airpods". Or a regular expression such as "/ticket (\\d+)/"',
        },
        to: {
          type: "string",
          description: 'What Voz types instead, such as "AirPods". \\n starts a new line. Leave out to delete the words',
        },
      },
      required: ["from"],
    },
    positional: ["from", "to"],
    run: ({ from, to }) => ({ changed: rules.add({ from, to: to ?? "" }), rule: describe({ from, to: to ?? "" }) }),
  });

  voz.registerTool({
    id: "remove",
    description: "Remove the replacement with these spellings",
    input: {
      type: "object",
      properties: { from: { type: "string", description: 'The spellings as listed, such as "air pods, airpods"' } },
      required: ["from"],
    },
    positional: ["from"],
    run: ({ from }) => ({ changed: rules.remove(from) }),
  });

  voz.registerTool({
    id: "test",
    description: "Show what Voz would type for this text with your replacements",
    readOnly: true,
    input: {
      type: "object",
      properties: { text: { type: "string", description: 'A dictation, such as "send it to my email"' } },
      required: ["text"],
    },
    positional: ["text"],
    run: ({ text }) => rules.apply(text),
  });
});
