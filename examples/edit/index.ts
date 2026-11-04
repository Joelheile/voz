import { defineExtension } from "voz";
import type { Context, ExtensionAPI, Field, TextRange } from "voz";

// After this long, "edit" changes the whole field instead of the last dictation
const recentDictation = 10 * 60_000;

const system = `You edit text in a text field for the user. You get the app, the field's text with the part to change marked as <target>, and an instruction, typed or spoken.

Output only the new text for <target>: no quotes, no preamble, no explanation. The text around <target> stays in the field, so never repeat or change it.

- "This", "it" and "the text" in the instruction mean <target> only, even when the instruction sounds broad.
- Change only what the instruction asks. If it names a part ("the last sentence", "the greeting"), change that part and copy the rest of <target> exactly.
- Keep the scale: one line stays one line, unless the instruction asks for more.
- Keep the meaning, voice, line breaks, @-mentions, links and names unless the instruction changes them. Keep the user's own phrasing where it already works: a smoother generic sentence is worse.
- Write in the language of <target>. An instruction in another language says what to change, not which language to use, unless it asks for a translation.
- Words about form ("shorter", "more formal") shape the text and never appear in it. Ignore false starts and self-corrections in spoken instructions.
- If the instruction asks for new content, such as a sign-off or a missing sentence, write <target> with it added where it belongs.
- Without an instruction, fix spelling, grammar and punctuation, and remove filler words. Keep the wording otherwise. If nothing needs fixing, return <target> unchanged.
- <past_edits> show earlier edits and the text the user kept. Where the user changed an edit, prefer their version.
- Never add facts. When a detail is missing, write a short placeholder like [time].
- Don't add em dashes.`;

type Target = { range: TextRange; text: string };
type Spoken = { text: string; app?: string; at: number };

export default defineExtension((voz) => {
  const settings = voz.settings({
    phrase: {
      type: "string",
      title: "Spoken phrase",
      description:
        'Start a dictation with it, such as "edit shorter". Change it if you start real sentences with it.',
      default: "edit",
    },
  });

  // The text to edit when nothing is selected: what you dictated last, then each edit of it
  let spoken: Spoken | undefined;

  voz.on("afterInsert", (event, ctx) => {
    spoken = { text: event.text, app: ctx.app.bundleID, at: Date.now() };
  });

  voz.registerCommand({
    phrase: settings.phrase,
    at: "start",
    run: (event, ctx) =>
      withField(ctx, (field) => edit(ctx, field, event.text.trim())),
  });

  voz.registerAction({
    id: "edit",
    name: "Edit",
    hotkey: "rightopt",
    when: "selection",
    run: (ctx) =>
      withField(ctx, async () => {
        if (!ctx.ask)
          return ctx.notify(
            'Say "edit" and what to change, such as "edit shorter"',
          );
        // The card comes back after each edit, so you can keep refining until you close it
        for (let round = 0; round < maxRounds; round++) {
          const answer = await ctx.ask({
            title: round === 0 ? "How should it change?" : "Change more?",
            fields: [
              {
                id: "instruction",
                label: "Leave empty to fix mistakes",
                type: "text",
                value: "",
              },
            ],
            buttons: [...presets, "Edit"],
          });
          if (!answer) return;
          const latest = await ctx.field();
          if (!latest) return ctx.notify("Click into a text field first");
          const instruction = answer.button === "Edit" ? String(answer.values.instruction ?? "").trim() : answer.button;
          if (!(await edit(ctx, latest, instruction))) return;
        }
      }),
  });

  async function edit(ctx: Context, field: Field, instruction: string) {
    const target = pickTarget(ctx, field);
    if (!target.text.trim()) {
      ctx.notify("Nothing to edit here");
      return false;
    }
    const onDevice = (await ctx.models()).provider === "apple";
    const around = onDevice ? 1200 : 20000;
    if (onDevice && target.text.length > 5000) {
      ctx.notify("Too long for Apple's model. Select less, or pick ChatGPT or Claude under Settings > AI model");
      return false;
    }
    const end = target.range.start + target.range.length;
    const marked = `${field.text.slice(0, target.range.start).slice(-around)}<target>${target.text}</target>${field.text.slice(end, end + around)}`;
    const prompt = [
      `<app>${ctx.app.name ?? "unknown"}${ctx.app.website ? ` (${ctx.app.website})` : ""}</app>`,
      `<field>\n${marked}\n</field>`,
      `<instruction>${instruction || "None. Fix mistakes only."}</instruction>`,
      await pastEdits(voz, onDevice ? 2 : 8),
    ]
      .filter(Boolean)
      .join("\n");
    const written = await ctx.busy(() =>
      ctx.generate({ instructions: system, prompt, schema, model: "fast" }),
    );
    if (written === undefined) return false;
    const edited = written.text.trim();
    if (!(await replace(ctx, target, edited, instruction))) return false;
    spoken = { text: edited, app: ctx.app.bundleID, at: Date.now() };
    return true;
  }

  // The selection wins, then your last dictation if it is still in this field, then the whole field
  function pickTarget(ctx: Context, field: Field): Target {
    const { start, length } = field.selection;
    if (length > 0)
      return {
        range: field.selection,
        text: field.text.slice(start, start + length),
      };
    const isRecent =
      spoken &&
      spoken.app === ctx.app.bundleID &&
      Date.now() - spoken.at < recentDictation;
    const at = isRecent ? field.text.lastIndexOf(spoken!.text) : -1;
    if (at >= 0)
      return {
        range: { start: at, length: spoken!.text.length },
        text: spoken!.text,
      };
    return { range: { start: 0, length: field.text.length }, text: field.text };
  }

  async function withField(
    ctx: Context,
    run: (field: Field) => Promise<unknown>,
  ) {
    if (!ctx.field) return ctx.notify("Edit needs a newer Voz");
    const field = await ctx.field();
    if (!field) return ctx.notify("Click into a text field first");
    try {
      await run(field);
    } catch (error) {
      ctx.notify(`Edit failed: ${(error as Error).message}`);
    }
  }
});

const presets = ["Shorter", "Clearer"];
const maxRounds = 10;

const schema = {
  type: "object",
  properties: { text: { type: "string", description: "The new text for <target>" } },
  required: ["text"],
} as const;

// What you kept or changed after earlier edits. Older Voz has no history.
async function pastEdits(voz: ExtensionAPI, count: number) {
  if (!voz.history) return "";
  const kept = (await voz.history({ source: voz.name, limit: 20 })).filter(
    (written) =>
      written.input &&
      written.input.length < 1000 &&
      ["kept", "edited", "sent"].includes(written.outcome ?? ""),
  );
  if (kept.length === 0) return "";
  const examples = kept.slice(0, count).map((written) =>
    [
      "<edit>",
      `<instruction>${written.instruction || "Fix mistakes only."}</instruction>`,
      `<before>${written.input}</before>`,
      `<user_kept>${written.text}</user_kept>`,
      "</edit>",
    ].join(""),
  );
  return `<past_edits>\n${examples.join("\n")}\n</past_edits>`;
}

// You may type while the model writes, so the result goes to a note instead of over your changes
async function replace(ctx: Context, target: Target, text: string, instruction: string) {
  const now = await ctx.field();
  const unchanged =
    now?.text.slice(
      target.range.start,
      target.range.start + target.range.length,
    ) === target.text;
  if (!now || !unchanged)
    return keepInNote(ctx, text, "The text changed, so the edit is in a note");
  if (!(await ctx.select(target.range))) {
    const isWholeField =
      target.range.start === 0 && target.range.length === now.text.length;
    if (!isWholeField)
      return keepInNote(
        ctx,
        text,
        "This app can't select text for Voz, so the edit is in a note",
      );
    ctx.press("cmd+a");
  }
  ctx.insert(text, { instruction });
  return true;
}

function keepInNote(ctx: Context, text: string, message: string) {
  ctx.openNote({ title: "Edit", text });
  ctx.notify(message);
  return false;
}
