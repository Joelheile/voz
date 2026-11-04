import { defineExtension } from "voz";
import type { Context, ExtensionAPI, Field } from "voz";
import { openMemory, skipList, watchScreen, type Memory } from "./memory";
import { isYours, openStyle, startLearning, styleFor, type Note } from "./style";

const system = `You write the user's next message in a conversation, as the user. You get the app, the text on screen before and after the reply field, what the user typed in the field, and sometimes what they said.

Output only the message: no quotes, no preamble, no explanation.

What the field holds (<field_text>):
- Prose addressed to the other person, however rough, is a draft. Keep its content, order, greeting and voice. Fix mistakes and finish it. A question in a draft is the user's question to the other person: keep it a question. If the draft is already right, return it unchanged.
- A note about what to write ("polite no", "ask about friday") or a one-word answer ("yes") is a gist. Write the full message it means, nothing more.
- Only a greeting, or empty: write the most likely reply.
- When unsure, treat it as a draft.
- <said> is what the user said aloud. It wins over <field_text>, and the message replaces the field. Words about form ("polite", "proper email", "shorter") shape the message and never appear in it. Ignore false starts and self-corrections.

What comes first, highest first: <said> and the facts on screen, <rules>, the draft and the relationship on screen, <learned_style>, <observed_style> and the user's messages, generic good writing.

Write as the user:
- Answer the latest message addressed to the user. If the last message is the user's own, write their natural next message.
- Screen text often lacks names. Work out who wrote what from <user_name>, <your_messages> and the flow. Never continue the other person's voice.
- Don't quote, restate or thank the other person for their message. No openers like "Great question". Answer what matters, not every point.
- Use only facts from the screen, <earlier>, <recent_work> and the gist. When a detail is missing, such as a time, write a short placeholder like [time].

Sound like the user:
- <your_messages> are the user's messages in this conversation, newest first. <your_writing> is what they wrote elsewhere. Match length, capitalization, punctuation, greetings, sign-offs and emoji. Copy how they sound, never their content.
- <learned_style> holds rules learned from how the user changed earlier drafts in this app. <observed_style> describes how they write here. Follow each rule, and copy the voice of its example, never its content.
- The situation wins over habit: condolences, bad news or an apology need care even in a casual chat. Don't pad to reach a usual length. A quick "sounds good" stays one line.

Fit the place:
- Chat: plain lines, no bullets, headings or sign-off.
- Email: greeting, body and sign-off, each only if missing, mirroring the thread. Nothing after the sign-off. Don't add one if <after_field> already has it.
- Comment: reads like a comment on the post.

Language: write in the language of <said> if it asks for one, else the message being answered, else the draft, else the conversation. Keep the user's mix of languages if they mix. The language of examples, rules and <recent_work> never counts.

Other context:
- <earlier> is this conversation, scrolled off screen, oldest first.
- <recent_work> is text from other windows the user had open lately. Use a fact from it only when the conversation is about that topic. Never say where it came from or copy its sentences.
- <rejected> is a reply the user asked you to replace. Write a clearly different one: another angle, length or wording.
- Keep @-mentions, links and names exactly. Don't add em dashes.`;

export default defineExtension((voz) => {
  const settings = voz.settings({
    name: {
      type: "string",
      title: "Your name in chats",
      description: "Helps Voz find your own messages and copy your tone.",
      default: "",
    },
    rules: {
      type: "string",
      title: "Always",
      description: 'Rules for every reply, such as "Sign emails as J. No exclamation marks."',
      default: "",
    },
    phrase: {
      type: "string",
      title: "Spoken phrase",
      description:
        'Start a dictation with it, such as "reply yes but next week". Change it if you start real sentences with it.',
      default: "reply",
    },
    remember: {
      type: "boolean",
      title: "Remember the screen",
      description: "Keeps what you see for 30 days, so replies know your work and earlier messages. Only on your Mac.",
      default: true,
    },
    skip: {
      type: "string",
      title: "Never remember",
      description: 'Apps to leave out, such as "Messages, WhatsApp".',
      default: "",
    },
  });

  const memory = openMemory(`${voz.paths.data}/screen.sqlite`);
  if (settings.remember) watchScreen(voz, memory, skipList(settings.skip));

  const style = openStyle(`${voz.paths.data}/style.sqlite`);
  startLearning(voz, style);
  const appName = (app: string) => style.get(`name:${app}`) ?? app;
  const describe = (note: Note) => ({
    id: String(note.id),
    title: note.rule,
    detail: `${appName(note.app)}${note.person ? `, with ${note.person}` : ""}, ${note.kind === "learned" ? "from your edits" : "from what you sent"}: "${note.example}"`,
  });

  voz.registerList?.({
    id: "style",
    title: "Writing style",
    description: "What Apple's model learned on your Mac from your edits and messages. Replies follow it.",
    items: () => style.notes().map(describe),
    remove: (id) => void style.remove(Number(id)),
  });

  voz.registerTool({
    id: "search",
    description: "Search what Reply saw on your screen in the last 30 days, best match first",
    input: {
      type: "object",
      properties: {
        query: { type: "string", description: 'Words on screen, such as "invoice". Leave out for the newest' },
        limit: { type: "number", description: "How many to return, 20 unless you say" },
      },
    },
    positional: ["query"],
    readOnly: true,
    run: ({ query, limit }) => memory.search({ query: query || undefined, limit }),
  });

  voz.registerTool({
    id: "style",
    description: "List what Reply learned about how you write, per app",
    readOnly: true,
    run: () => style.notes().map(describe),
  });

  voz.registerTool({
    id: "forget-style",
    description: "Delete learned writing style rules that contain these words, or all of them",
    input: {
      type: "object",
      properties: { words: { type: "string", description: 'Words in the rule or its example, such as "emoji". Leave out for all' } },
    },
    positional: ["words"],
    run: ({ words }) => ({ forgot: style.forget(words) }),
  });

  voz.registerTool({
    id: "forget",
    description: "Delete everything Reply saw on your screen",
    run: () => ({ forgot: memory.forget() }),
  });

  // The reply Voz inserted last, so tapping again while it is still in the field writes a different one
  let last: { output: string; typed: string; said: string; rejected: string[] } | undefined;

  // The model decides whether what you typed is a gist to write out or a draft to finish
  voz.registerAction({
    id: "reply",
    name: "Reply",
    hotkey: "rightopt",
    run: (ctx) => withField(ctx, (field) => reply(ctx, field, "")),
  });

  voz.registerCommand({
    phrase: settings.phrase,
    at: "start",
    run: (event, ctx) =>
      withField(ctx, (field) => reply(ctx, field, event.text.trim())),
  });

  async function reply(ctx: Context, field: Field, spoken: string) {
    const again = !spoken && last !== undefined && field.text.trim() === last.output;
    const typed = again ? last!.typed : field.text.trim();
    const said = again ? last!.said : spoken;
    const rejected = again ? [...last!.rejected, last!.output] : [];
    const app = ctx.app.bundleID;
    if (app && ctx.app.name) style.set(`name:${app}`, ctx.app.name);
    if (app && again) style.reject(app, last!.output);
    if (!field.before.trim() && !typed && !said)
      return ctx.notify("No conversation to reply to here");
    const onDevice = (await ctx.models()).provider === "apple";
    const size = onDevice ? small : large;
    const prompt = [
      `<app>${ctx.app.name ?? "unknown"}${ctx.app.website ? ` (${ctx.app.website})` : ""}</app>`,
      field.window && `<window>${field.window}</window>`,
      settings.name && `<user_name>${settings.name}</user_name>`,
      `<today>${new Date().toDateString()}</today>`,
      settings.rules && `<rules>${settings.rules}</rules>`,
      ...styleFor(style, app, field.thread?.title),
      ...(await pastWriting(voz, field, size)),
      ...seenBefore(memory, field, `${typed} ${said}`, size),
      `<before_field>\n${field.before.slice(-size.before)}\n</before_field>`,
      `<after_field>\n${field.after.slice(0, size.after)}\n</after_field>`,
      `<field_text>\n${typed}\n</field_text>`,
      said && `<said>${said}</said>`,
      ...rejected.slice(-2).map((text) => `<rejected>${text}</rejected>`),
    ]
      .filter(Boolean)
      .join("\n");
    const written = await ctx.busy(() =>
      ctx.generate({ instructions: system, prompt, schema, model: "balanced" }),
    );
    if (written === undefined) return;
    const output = written.text.trim();
    if (await replaceField(ctx, field.text, output, said || typed)) last = { output, typed, said, rejected };
  }

  async function withField(
    ctx: Context,
    run: (field: Field) => Promise<unknown>,
  ) {
    if (!ctx.field) return ctx.notify("Reply needs a newer Voz");
    const field = await ctx.field();
    if (!field) return ctx.notify("Click into a reply field first");
    try {
      await run(field);
    } catch (error) {
      ctx.notify(`Reply failed: ${(error as Error).message}`);
    }
  }
});

const schema = {
  type: "object",
  properties: { text: { type: "string", description: "The message, as the user would send it" } },
  required: ["text"],
} as const;

// Characters of context. Apple's on-device model reads about 4,000 tokens, including the instructions and the reply.
type Size = { before: number; after: number; message: number; messages: number; samples: number; earlier: number; work: number };
const small: Size = { before: 1800, after: 300, message: 300, messages: 5, samples: 2, earlier: 500, work: 600 };
const large: Size = { before: 40000, after: 4000, message: 1000, messages: 20, samples: 3, earlier: 12000, work: 8000 };

// With fewer of your messages in this conversation, the model also gets dictations from elsewhere for your general style
const fewMessages = 5;

// Your messages in this conversation, and a few from elsewhere when there are few here. Older Voz has no history.
async function pastWriting(voz: ExtensionAPI, field: Field, size: Size) {
  if (!voz.history) return [];
  const [thread, recent] = await Promise.all([
    field.thread ? voz.history({ thread: field.thread.id, limit: 20 }) : [],
    voz.history({ limit: 50 }),
  ]);
  const yours = thread.filter((written) => isYours(written) && written.text.length < size.message).slice(0, size.messages);
  const messages = yours.map((written) => `<message>${written.text}</message>`);
  const elsewhere = yours.length < fewMessages
    ? recent
        .filter((written) => written.kind === "dictation" && written.thread !== field.thread?.id && written.text.length < size.message)
        .slice(0, size.samples)
        .map((written) => `<sample>${written.text}</sample>`)
    : [];
  return [
    messages.length > 0 && `<your_messages>\n${messages.join("\n")}\n</your_messages>`,
    elsewhere.length > 0 && `<your_writing>\n${elsewhere.join("\n")}\n</your_writing>`,
  ];
}

// What Reply saw on screen: this conversation before it scrolled away, and your other work on the same topics
function seenBefore(memory: Memory, field: Field, gist: string, size: Size) {
  const query = keywords(`${field.before.slice(-1500)} ${gist}`).join(" ");
  const since = Date.now() - 14 * 86_400_000;
  const thread = field.thread ? memory.search({ thread: field.thread.id, limit: 5 }) : [];
  const work = query ? memory.search({ query, since, limit: 12 }) : [];
  const onScreen = field.before.slice(-size.before);
  const earlier = thread
    .flatMap((seen) => seen.text.split("\n"))
    .filter((line, index, lines) => line.trim() && !onScreen.includes(line) && lines.indexOf(line) === index)
    .join("\n")
    .slice(-size.earlier);
  const notes: string[] = [];
  let left = size.work;
  for (const seen of work.filter((seen) => !field.thread || seen.thread !== field.thread.id)) {
    if (left <= 0) break;
    const note = `<seen app="${seen.app}" window="${seen.window}">${seen.text.slice(0, left)}</seen>`;
    notes.push(note);
    left -= note.length;
  }
  return [
    earlier && `<earlier>\n${earlier}\n</earlier>`,
    notes.length > 0 && `<recent_work>\n${notes.join("\n")}\n</recent_work>`,
  ];
}

const common = new Set(["about", "after", "also", "been", "before", "could", "from", "have", "here", "just", "like", "more", "only", "some", "that", "them", "then", "there", "they", "this", "what", "when", "where", "which", "will", "with", "would", "your", "aber", "auch", "dann", "dass", "doch", "eine", "einen", "haben", "nicht", "noch", "oder", "schon", "sein", "sind", "wenn", "wird", "heute", "morgen", "today", "tomorrow", "thanks", "danke"]);

// The latest distinct words worth searching for, newest first
function keywords(text: string) {
  const words = text.toLowerCase().match(/[\p{L}\p{N}]{4,}/gu) ?? [];
  return [...new Set(words.reverse())].filter((word) => !common.has(word) && !/^\d+$/.test(word)).slice(0, 12);
}

// You may type while the model writes, so the reply goes to a note instead of over your changes
async function replaceField(ctx: Context, original: string, text: string, instruction: string) {
  const now = await ctx.field();
  if (now?.text !== original) {
    ctx.openNote({ title: "Reply", text });
    ctx.notify("The field changed, so the reply is in a note");
    return false;
  }
  if (!(await ctx.select({ start: 0, length: now.text.length })))
    ctx.press("cmd+a");
  ctx.insert(text, instruction ? { instruction } : undefined);
  return true;
}
