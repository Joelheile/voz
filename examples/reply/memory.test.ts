import { expect, test } from "bun:test";
import { matchExpression, merge, openMemory, skipList } from "./memory";

const screen = (text: string, window = "Anna") => ({
  app: "Slack",
  window,
  text,
});

test("captures of the same window within minutes become one, with scrolled-away lines kept above", () => {
  const memory = openMemory(":memory:");
  memory.save(screen("hi\nare you coming?"), 0);
  memory.save(screen("are you coming?\nyes, at 6"), 60_000);
  expect(memory.search()).toEqual([
    {
      app: "Slack",
      window: "Anna",
      text: "hi\nare you coming?\nyes, at 6",
      at: 60_000,
    },
  ]);
});

test("a search finds captures with any of its words, cut to the part that matches", () => {
  const memory = openMemory(":memory:");
  memory.save(screen("The invoice for October is attached", "Mail"), 0);
  memory.save(screen("lunch?", "Ben"), 0);
  expect(
    memory
      .search({ query: "October invoices invoice" })
      .map((seen) => seen.window),
  ).toEqual(["Mail"]);
  expect(memory.search({ query: "!" })).toEqual([]);
});

test("forget deletes everything and counts captures, not index rows", () => {
  const memory = openMemory(":memory:");
  memory.save(screen("one", "A"), 0);
  memory.save(screen("two", "B"), 0);
  expect(memory.forget()).toBe(2);
  expect(memory.search()).toEqual([]);
});

test("merge keeps the new text whole", () => {
  expect(merge("a\nb", "b\nc")).toBe("a\nb\nc");
  expect(merge("a", "a")).toBe("a");
});

test("search words are quoted, so FTS syntax in your text can't break the query", () => {
  expect(matchExpression('invoice OR "x" NEAR')).toBe(
    '"invoice" OR "near" OR "or"',
  );
});

test("skip names apps case-insensitively and ignores empty entries", () => {
  expect(skipList(" Messages, whatsapp ,,")).toEqual(["messages", "whatsapp"]);
});
