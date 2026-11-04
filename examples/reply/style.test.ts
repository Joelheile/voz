import { expect, test } from "bun:test";
import type { ExtensionAPI, Written } from "voz";
import { learn, observe, openStyle, styleFor } from "./style";

const slack = "com.tinyspeck.slackmacgap";
const today = new Date("2026-11-04T12:00:00Z");

function fakeVoz(history: Written[], replies: unknown[]) {
  const prompts: { prompt: string; model?: string }[] = [];
  const voz = {
    name: "voz-reply",
    history: async ({ source }: { source?: string } = {}) =>
      history.filter((written) => !source || written.source === source),
    generate: async (request: { prompt: string; model?: string }) => {
      prompts.push(request);
      return replies.shift();
    },
  } as unknown as ExtensionAPI;
  return { voz, prompts };
}

const draft = (
  output: string,
  text: string,
  at: number,
  outcome: Written["outcome"] = "sent",
): Written => ({
  kind: "draft",
  source: "voz-reply",
  app: slack,
  threadTitle: "Anna",
  output,
  text,
  outcome,
  at,
});

test("a changed draft teaches a rule on your Mac, and each draft teaches once", async () => {
  const style = openStyle(":memory:");
  const { voz, prompts } = fakeVoz(
    [
      draft("Hello Anna, sounds great!", "sounds good", 10),
      draft("ok", "ok", 5, "unknown"),
    ],
    [
      {
        changed: true,
        rules: [
          { rule: "Write in lowercase, no greeting.", example: "sounds good" },
        ],
      },
    ],
  );
  await learn(voz, style, today);
  expect(prompts).toHaveLength(1);
  expect(prompts[0]!.model).toBe("on-device");
  expect(prompts[0]!.prompt).toContain(
    '<correction to="Anna"><draft>Hello Anna, sounds great!</draft><user_sent>sounds good</user_sent>',
  );
  expect(style.notes(slack)).toEqual([
    {
      id: 1,
      app: slack,
      kind: "learned",
      rule: "Write in lowercase, no greeting.",
      example: "sounds good",
      seen: "2026-11-04",
    },
  ]);
  await learn(voz, style, today);
  expect(prompts).toHaveLength(1);
});

test("a reply you tapped past counts as rejected, and an unchanged list stays", async () => {
  const style = openStyle(":memory:");
  style.replace(
    slack,
    "learned",
    [{ rule: "Sign off with Cheers.", example: "Cheers, J" }],
    "2026-11-01",
  );
  style.reject(slack, "Sure thing! Cheers, J", 20);
  const { voz, prompts } = fakeVoz([], [{ changed: false, rules: [] }]);
  await learn(voz, style, today);
  expect(prompts[0]!.prompt).toContain(
    '- Sign off with Cheers. Example: "Cheers, J"',
  );
  expect(prompts[0]!.prompt).toContain(
    "<rejected>Sure thing! Cheers, J</rejected>",
  );
  expect(style.notes(slack).map((note) => note.rule)).toEqual([
    "Sign off with Cheers.",
  ]);
  expect(style.rejections(today.getTime())).toEqual([]);
});

test("a draft Voz still watches waits for the next run, and a kept draft goes along as confirmation", async () => {
  const style = openStyle(":memory:");
  const fresh = draft("Hey!", "hey", today.getTime() - 30_000);
  const { voz, prompts } = fakeVoz(
    [fresh, draft("See you then", "See you then", 15, "kept"), draft("Hi Anna!", "hi", 10)],
    [{ changed: false, rules: [] }, { changed: false, rules: [] }],
  );
  await learn(voz, style, today);
  expect(prompts[0]!.prompt).not.toContain("Hey!");
  expect(prompts[0]!.prompt).toContain('<kept to="Anna">See you then</kept>');
  await learn(voz, style, new Date(today.getTime() + 5 * 60_000));
  expect(prompts[1]!.prompt).toContain("<draft>Hey!</draft>");
  expect(prompts[1]!.prompt).not.toContain("Hi Anna!");
});

test("what you send per app becomes observed style, tagged with who it went to", async () => {
  const style = openStyle(":memory:");
  const sent = ["yo", "on it", "lol yes"].map(
    (text, at): Written => ({
      kind: "dictation",
      text,
      at,
      app: slack,
      threadTitle: "Ben",
    }),
  );
  const { voz, prompts } = fakeVoz(sent, [
    {
      rules: [
        { rule: "Very short and casual.", example: "on it", person: "Ben" },
      ],
    },
  ]);
  await observe(voz, style, today);
  expect(prompts[0]!.prompt).toContain('<message to="Ben">on it</message>');
  expect(style.get("observed")).toBe(String(today.getTime()));
  expect(styleFor(style, slack, "Anna")).toEqual([false, false]);
  expect(styleFor(style, slack, "ben")).toEqual([
    false,
    '<observed_style>\n- With Ben: Very short and casual. Example: "on it"\n</observed_style>',
  ]);
});

test("forget deletes rules with your words, or all of them", () => {
  const style = openStyle(":memory:");
  style.replace(
    slack,
    "learned",
    [
      { rule: "No emoji.", example: "ok" },
      { rule: "Lowercase.", example: "sure" },
    ],
    "2026-11-04",
  );
  expect(style.forget("EMOJI")).toBe(1);
  expect(style.forget()).toBe(1);
  expect(style.notes()).toEqual([]);
});
