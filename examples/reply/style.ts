import { Database } from "bun:sqlite";
import type { ExtensionAPI, Written } from "voz";

// How you write, per app and sometimes per person. Apple's model learns it on your Mac in the background,
// from the drafts you changed or rejected and from what you sent. The model you picked writes with it.

const learnEvery = 5 * 60_000;
const observeEvery = 6 * 3_600_000;
const firstRun = 30_000;
// Voz watches a draft for up to two minutes before it knows what you did with it
const settling = 2 * 60_000;
// Per app. Above it, rules that say the same thing merge.
const maxLearned = 8;
const maxObserved = 3;
// Apple's model reads about 4,000 tokens, so each call sees a few short messages
const evidencePerCall = 4;
const messagesPerCall = 12;
const maxChars = 400;

export type Note = {
  id: number;
  app: string;
  person?: string;
  kind: "learned" | "observed";
  rule: string;
  example: string;
  seen: string;
};
export type Rule = { rule: string; example: string; person?: string };
export type Style = ReturnType<typeof openStyle>;

type Row = Omit<Note, "person"> & { person: string | null };

export function openStyle(path: string) {
  const db = new Database(path, { create: true });
  db.run("PRAGMA journal_mode = WAL");
  db.run(
    "CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, app TEXT NOT NULL, person TEXT, kind TEXT NOT NULL, rule TEXT NOT NULL, example TEXT NOT NULL, seen TEXT NOT NULL)",
  );
  db.run(
    "CREATE TABLE IF NOT EXISTS rejected (app TEXT NOT NULL, text TEXT NOT NULL, at INTEGER NOT NULL)",
  );
  db.run(
    "CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
  );

  function notes(app?: string): Note[] {
    const rows = (
      app
        ? db
            .query("SELECT * FROM notes WHERE app = ? ORDER BY kind, id")
            .all(app)
        : db.query("SELECT * FROM notes ORDER BY app, kind, id").all()
    ) as Row[];
    return rows.map(({ person, ...note }) =>
      person ? { ...note, person } : note,
    );
  }

  function replace(
    app: string,
    kind: Note["kind"],
    rules: Rule[],
    seen: string,
  ) {
    db.transaction(() => {
      db.run("DELETE FROM notes WHERE app = ? AND kind = ?", [app, kind]);
      for (const { rule, example, person } of rules)
        db.run(
          "INSERT INTO notes (app, person, kind, rule, example, seen) VALUES (?, ?, ?, ?, ?, ?)",
          [
            app,
            person?.trim() || null,
            kind,
            rule.trim(),
            example.trim(),
            seen,
          ],
        );
    })();
  }

  function remove(id: number) {
    return db.run("DELETE FROM notes WHERE id = ?", [id]).changes > 0;
  }

  // Without words, everything Reply learned
  function forget(words = "") {
    const like = `%${words.trim().toLowerCase()}%`;
    return db.run(
      "DELETE FROM notes WHERE lower(rule || ' ' || example) LIKE ?",
      [like],
    ).changes;
  }

  function reject(app: string, text: string, at = Date.now()) {
    db.run("INSERT INTO rejected (app, text, at) VALUES (?, ?, ?)", [
      app,
      text.slice(0, maxChars),
      at,
    ]);
  }

  function rejections(until: number) {
    return db
      .query("SELECT app, text, at FROM rejected WHERE at <= ? ORDER BY at")
      .all(until) as {
      app: string;
      text: string;
      at: number;
    }[];
  }

  function learned(until: number) {
    db.run("DELETE FROM rejected WHERE at <= ?", [until]);
    set("learned", String(until));
  }

  function get(key: string) {
    return (
      db.query("SELECT value FROM state WHERE key = ?").get(key) as {
        value: string;
      } | null
    )?.value;
  }

  function set(key: string, value: string) {
    db.run(
      "INSERT INTO state (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      [key, value],
    );
  }

  return { notes, replace, remove, forget, reject, rejections, learned, get, set };
}

// Learns every few minutes while Voz runs. Older Voz can't run a model in the background.
export function startLearning(voz: ExtensionAPI, style: Style) {
  if (!voz.history || !voz.generate) return;
  let learning = false;
  const tick = async () => {
    if (learning) return;
    learning = true;
    try {
      await learn(voz, style);
      if (Date.now() - Number(style.get("observed") ?? 0) > observeEvery)
        await observe(voz, style);
    } catch {
      // Macs without Apple Intelligence can't learn. Replies still work.
    } finally {
      learning = false;
    }
  };
  setTimeout(tick, firstRun);
  setInterval(tick, learnEvery);
}

const ruleSchema = {
  type: "object",
  properties: {
    rule: {
      type: "string",
      description: "One short instruction about how the user writes",
    },
    example: {
      type: "string",
      description:
        "Verbatim words the user wrote that show it, 25 words or fewer",
    },
    person: {
      type: "string",
      description:
        "Only when the rule holds for one person: their name as tagged",
    },
  },
  required: ["rule", "example"],
} as const;

const learnSchema = {
  type: "object",
  properties: {
    changed: {
      type: "boolean",
      description: "False when nothing durable changed",
    },
    rules: { type: "array", items: ruleSchema },
  },
  required: ["changed", "rules"],
} as const;

const rulesSchema = {
  type: "object",
  properties: { rules: { type: "array", items: ruleSchema } },
  required: ["rules"],
} as const;

const learnInstructions = `You keep a short list of rules about how one user writes in one app. You get the current list, drafts an assistant wrote next to what the user sent instead, drafts the user rejected, and drafts they kept as written. Return the full updated list.

- Capture durable style, never content: length, tone, greetings, sign-offs, punctuation, capitalization, emoji, word choice.
- Ignore one-off requests and changes about the topic.
- Keep each rule at the scope the evidence shows. Set person only when the change clearly holds for that person.
- Never record a language. The conversation decides it.
- A rejected draft that followed a rule weakens it. Drop the rule when the evidence is against it.
- When the user's choices conflict, state the condition, or keep neither.
- Every rule needs a verbatim example from what the user sent, 25 words or fewer, with names replaced by <first name>.
- Keep rules the new evidence doesn't touch word for word.
- If nothing durable changed, set changed to false.`;

const observeInstructions = `You describe how one user writes in one app, from messages they sent. Each message is tagged with who it went to.

- Write 1 to 3 rules about tone, formality, length, greetings, sign-offs, punctuation, capitalization and emoji.
- Each rule has a verbatim example from the messages, 25 words or fewer, with names replaced by <first name>.
- Set person only when the habit shows only in messages to that person.
- Never describe the language or what the messages are about.
- If the messages show no clear habit, return no rules.`;

const mergeInstructions = `You tidy a list of rules about how one user writes. Merge rules that say the same thing into one, with the clearest wording and one of their examples. Keep every other rule word for word, with its person. Invent nothing.`;

// Drafts you changed, removed or tapped past since the last run, one app at a time. Drafts Voz still watches wait for the next run.
export async function learn(
  voz: ExtensionAPI,
  style: Style,
  today = new Date(),
) {
  const since = Number(style.get("learned") ?? 0);
  const until = today.getTime() - settling;
  const drafts = (await voz.history({ source: voz.name, limit: 50 })).filter(
    (written) =>
      written.at > since &&
      written.at <= until &&
      written.app &&
      written.output &&
      written.outcome !== "unknown",
  );
  const rejected = style.rejections(until);
  const apps = new Set([
    ...drafts.map((written) => written.app!),
    ...rejected.map((row) => row.app),
  ]);
  for (const app of apps) {
    const here = drafts.filter((written) => written.app === app);
    const kept = here.filter((written) => isYours(written) && written.text === written.output);
    const evidence = [
      ...here
        .filter((written) => !kept.includes(written))
        .map((written) =>
          written.outcome === "removed"
            ? `<rejected>${clip(written.output!)}</rejected>`
            : `<correction${tag(written)}><draft>${clip(written.output!)}</draft><user_sent>${clip(written.text)}</user_sent></correction>`,
        ),
      ...rejected
        .filter((row) => row.app === app)
        .map((row) => `<rejected>${row.text}</rejected>`),
    ].slice(-evidencePerCall);
    // Kept drafts only confirm rules, so they don't start a run on their own
    if (evidence.length === 0) continue;
    evidence.push(...kept.slice(0, 2).map((written) => `<kept${tag(written)}>${clip(written.text)}</kept>`));
    const current = style.notes(app).filter((note) => note.kind === "learned");
    const result = await voz.generate({
      instructions: learnInstructions,
      prompt: [`<current>\n${list(current)}\n</current>`, ...evidence].join(
        "\n",
      ),
      schema: learnSchema,
      model: "on-device",
    });
    if (!result.changed) continue;
    style.replace(app, "learned", result.rules, day(today));
    if (result.rules.length > maxLearned) await merge(voz, style, app, today);
  }
  style.learned(until);
}

// Your recent messages per app, tagged by who they went to
export async function observe(
  voz: ExtensionAPI,
  style: Style,
  today = new Date(),
) {
  const sent = (await voz.history({ limit: 100 })).filter(
    (written) =>
      written.app && isYours(written) && written.text.length < maxChars,
  );
  const last = Number(style.get("observed") ?? 0);
  if (!sent.some((written) => written.at > last)) return;
  for (const app of new Set(sent.map((written) => written.app!))) {
    const messages = sent.filter((written) => written.app === app);
    if (messages.length < 3) continue;
    const prompt = messages
      .slice(0, messagesPerCall)
      .map((written) => `<message${tag(written)}>${written.text}</message>`)
      .join("\n");
    const result = await voz.generate({
      instructions: observeInstructions,
      prompt,
      schema: rulesSchema,
      model: "on-device",
    });
    style.replace(
      app,
      "observed",
      result.rules.slice(0, maxObserved),
      day(today),
    );
  }
  style.set("observed", String(today.getTime()));
}

async function merge(
  voz: ExtensionAPI,
  style: Style,
  app: string,
  today: Date,
) {
  const current = style.notes(app).filter((note) => note.kind === "learned");
  const result = await voz.generate({
    instructions: mergeInstructions,
    prompt: `<rules>\n${list(current)}\n</rules>`,
    schema: rulesSchema,
    model: "on-device",
  });
  style.replace(app, "learned", result.rules.slice(0, maxLearned), day(today));
}

// What the writer gets: rules for this app, and for this person when the conversation is with them. Learned rules come first.
export function styleFor(
  style: Style,
  app: string | undefined,
  person: string | undefined,
) {
  if (!app) return [];
  const notes = style
    .notes(app)
    .filter(
      (note) =>
        !note.person || note.person.toLowerCase() === person?.toLowerCase(),
    );
  const block = (kind: Note["kind"]) => {
    const lines = notes.filter((note) => note.kind === kind).map(line);
    return (
      lines.length > 0 &&
      `<${kind}_style>\n${lines.join("\n")}\n</${kind}_style>`
    );
  };
  return [block("learned"), block("observed")];
}

// A draft you removed, or one Voz couldn't follow, isn't something you wrote
export const isYours = (written: Written) =>
  written.kind === "dictation" ||
  written.outcome === "kept" ||
  written.outcome === "edited" ||
  written.outcome === "sent";

const line = (note: Pick<Note, "rule" | "example" | "person">) =>
  `- ${note.person ? `With ${note.person}: ` : ""}${note.rule} Example: "${note.example}"`;
const list = (notes: Note[]) => notes.map(line).join("\n") || "(empty)";
const tag = (written: Written) =>
  written.threadTitle ? ` to="${written.threadTitle}"` : "";
const clip = (text: string) => text.slice(0, maxChars);
const day = (date: Date) => date.toISOString().slice(0, 10);
