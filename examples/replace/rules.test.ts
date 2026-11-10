import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { apply, compile, describe, RuleStore, type Rule } from "./rules";

const run = (text: string, ...rules: Rule[]) => apply(text, rules.map(compile));

test("replaces whole words and phrases, ignoring case", () => {
  expect(run("I love my air pods.", { from: "air pods", to: "AirPods" })).toBe("I love my AirPods.");
  expect(run("Air  Pods are great", { from: "air pods", to: "AirPods" })).toBe("AirPods are great");
  expect(run("the colour of colourful", { from: "colour", to: "color" })).toBe("the color of colourful");
  expect(run("Ask Eric and Erica", { from: "eric", to: "Erick" })).toBe("Ask Erick and Erica");
});

test("several spellings separated by commas all become the replacement", () => {
  const rule = { from: "raycast, reycast, recast", to: "Raycast" };
  expect(run("Open recast and reycast", rule)).toBe("Open Raycast and Raycast");
});

test("matches words with umlauts and accents as whole words", () => {
  expect(run("Grüße an Müller und Müllers", { from: "müller", to: "Mueller" })).toBe("Grüße an Mueller und Müllers");
});

test("keeps a capital at the start of a sentence for plain words", () => {
  expect(run("Gonna be late. I'm gonna run.", { from: "gonna", to: "going to" })).toBe("Going to be late. I'm going to run.");
  expect(run("Ebay has it", { from: "ebay", to: "eBay" })).toBe("eBay has it");
});

test("a dictation that is only the shortcut becomes just the snippet", () => {
  const email = { from: "my email", to: "leonard@example.com" };
  expect(run("My email.", email)).toBe("leonard@example.com");
  expect(run("Send it to my email please.", email)).toBe("Send it to leonard@example.com please.");
  const signature = { from: "my signature", to: "Best,\\nLeonard" };
  expect(run("My signature", signature)).toBe("Best,\nLeonard");
});

test("an empty replacement deletes the words and tidies the gaps", () => {
  const fillers = { from: "basically, like", to: "" };
  expect(run("Basically, we ship on Friday.", fillers)).toBe("We ship on Friday.");
  expect(run("We ship, like, on Friday.", fillers)).toBe("We ship, on Friday.");
});

test("regular expressions use their flags and $1", () => {
  expect(run("yeah, ya and yea", { from: "/\\b(yeah|ya|yea)\\b/", to: "yes" })).toBe("yes, yes and yes");
  expect(run("IT says it works", { from: "/\\bIT\\b/g", to: "Information Technology" })).toBe("Information Technology says it works");
  expect(run("ticket 42 and ticket 7", { from: "/ticket (\\d+)/", to: "VOZ-$1" })).toBe("VOZ-42 and VOZ-7");
  expect(() => compile({ from: "/(/", to: "x" })).toThrow("not a valid regular expression");
});

test("rejects an empty From with a message that says what to do", () => {
  expect(() => compile({ from: " ", to: "x" })).toThrow("From field is empty");
  expect(() => compile({ from: " , ", to: "x" })).toThrow("only commas");
});

test("the store adds, updates, removes and reloads a file edited by hand", () => {
  const path = join(mkdtempSync(join(tmpdir(), "voz-replace-")), "rules.json");
  const store = new RuleStore(path);
  expect(store.apply("air pods")).toBe("air pods");
  expect(store.add({ from: "air pods", to: "AirPods" })).toBe(true);
  expect(store.add({ from: "air pods", to: "AirPods" })).toBe(false);
  expect(store.add({ from: "Air Pods", to: "AirPods Pro" })).toBe(true);
  expect(store.all()).toEqual([{ from: "Air Pods", to: "AirPods Pro" }]);
  expect(store.apply("my air pods")).toBe("my AirPods Pro");
  expect(store.remove("AIR PODS")).toBe(true);
  expect(store.remove("air pods")).toBe(false);
  writeFileSync(path, JSON.stringify([{ from: "voss", to: "Voz" }, { from: "/(/", to: "broken" }, { nope: 1 }]));
  expect(store.apply("I use voss")).toBe("I use Voz");
  expect(() => store.add({ from: "/(/", to: "x" })).toThrow();
});

test("describes rules for the list, showing deletions and line breaks", () => {
  expect(describe({ from: "um, uh", to: "" })).toBe("um, uh → (delete)");
  expect(describe({ from: "sig", to: "Best,\nLeo" })).toBe("sig → Best, ⏎ Leo");
});
