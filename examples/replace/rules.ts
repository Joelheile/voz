import { readFileSync, renameSync, statSync, writeFileSync } from "node:fs";

/**
 * One replacement. `from` is one or more spellings separated by commas, or a regular expression written as `/pattern/flags`.
 * `to` is the text Voz types instead. Empty deletes the match. `\n` in `to` starts a new line.
 */
export type Rule = { from: string; to: string };

type Compiled = { rule: Rule; pattern: RegExp; whole: RegExp | null; literal: boolean; to: string };

const wordChar = "[\\p{L}\\p{N}_]";

/** Writes `\n` and `\t` the way people type them in a one-line field */
function unescape(text: string): string {
  return text.replace(/\\(n|t|\\)/g, (_, c: string) => (c === "n" ? "\n" : c === "t" ? "\t" : "\\"));
}

function regex(from: string): RegExp | null {
  const match = from.match(/^\/(.+)\/([a-z]*)$/s);
  if (!match) return null;
  const [, body, given] = match;
  // Without flags it ignores case like the plain spellings. Give flags, such as /IT/g, to match case.
  const flags = given ? (given.includes("g") ? given : `${given}g`) : "gi";
  try {
    return new RegExp(body, flags.includes("u") ? flags : `${flags}u`);
  } catch (error) {
    throw new Error(`"${from}" is not a valid regular expression: ${(error as Error).message}`);
  }
}

function variants(from: string): string[] {
  return from
    .split(",")
    .map((variant) => variant.trim())
    .filter(Boolean);
}

function escape(variant: string): string {
  return variant.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\s+/g, "\\s+");
}

export function compile(rule: Rule): Compiled {
  const from = rule.from.trim();
  if (!from) throw new Error("Say what to replace: the From field is empty.");
  const to = unescape(rule.to);
  const pattern = regex(from);
  if (pattern) return { rule, pattern, whole: null, literal: false, to };
  const spellings = variants(from);
  if (spellings.length === 0) throw new Error("Say what to replace: the From field has only commas.");
  // Longest first, so "air pods pro" wins over "air pods"
  const alternatives = spellings.sort((a, b) => b.length - a.length).map(escape).join("|");
  return {
    rule,
    pattern: new RegExp(`(?<!${wordChar})(?:${alternatives})(?!${wordChar})`, "giu"),
    whole: new RegExp(`^\\s*(?:${alternatives})\\s*[.!?]?\\s*$`, "iu"),
    literal: true,
    to,
  };
}

/** "gonna" → "going to" becomes "Going to" at the start of a sentence. Names, emails and links keep their case. */
function matchCase(found: string, to: string): string {
  const startsUpper = /^\p{Lu}/u.test(found);
  const plainLowercase = /^[\p{Ll}' ]+$/u.test(to);
  return startsUpper && plainLowercase ? to[0].toUpperCase() + to.slice(1) : to;
}

/** Deleting words leaves gaps such as "so , we" or a sentence starting with a comma */
function tidy(text: string, wasCapitalized: boolean): string {
  let tidied = text
    .replace(/[ \t]{2,}/g, " ")
    .replace(/[ \t]+([,.!?;:])/g, "$1")
    .replace(/([,;:])(?:[ \t]*[,;:])+/g, "$1")
    .replace(/([.!?]\s+)[,;:]\s*/g, "$1")
    .replace(/^[\s,;:]+/, "")
    .replace(/[ \t]+$/gm, "");
  if (wasCapitalized) tidied = tidied.replace(/^\p{Ll}/u, (letter) => letter.toUpperCase());
  return tidied;
}

export function apply(text: string, rules: Compiled[]): string {
  // A dictation that is only the shortcut, such as "My email.", becomes just the snippet, without the period
  for (const rule of rules) {
    if (rule.whole?.test(text)) return rule.to;
  }
  let result = text;
  let deleted = false;
  for (const rule of rules) {
    const before = result;
    // Regular expressions get JavaScript's own $1 and $& in the replacement
    result = rule.literal ? result.replace(rule.pattern, (found: string) => matchCase(found, rule.to)) : result.replace(rule.pattern, rule.to);
    if (rule.to === "" && result !== before) deleted = true;
  }
  return deleted ? tidy(result, /^\p{Lu}/u.test(text.trimStart())) : result;
}

/** Keeps the rules in a JSON file, and reads it again only when it changed, so each dictation costs one stat */
export class RuleStore {
  private compiled: Compiled[] = [];
  /** Modification time and size of the file last read, so an edit by hand is noticed */
  private loaded = "";

  constructor(private readonly path: string) {}

  all(): Rule[] {
    this.refresh();
    return this.compiled.map(({ rule }) => rule);
  }

  apply(text: string): string {
    this.refresh();
    return this.compiled.length ? apply(text, this.compiled) : text;
  }

  /** Adds a rule, or changes the replacement of the rule with the same From. Returns false when nothing changed. */
  add(rule: Rule): boolean {
    const added = compile({ from: rule.from.trim(), to: rule.to });
    const rules = this.all();
    const index = rules.findIndex((existing) => same(existing.from, added.rule.from));
    if (index >= 0 && rules[index].to === rule.to && rules[index].from === added.rule.from) return false;
    if (index >= 0) rules[index] = added.rule;
    else rules.push(added.rule);
    this.write(rules);
    return true;
  }

  remove(from: string): boolean {
    const rules = this.all();
    const kept = rules.filter((rule) => !same(rule.from, from));
    if (kept.length === rules.length) return false;
    this.write(kept);
    return true;
  }

  private write(rules: Rule[]) {
    const temporary = `${this.path}.tmp`;
    writeFileSync(temporary, `${JSON.stringify(rules, null, 2)}\n`);
    renameSync(temporary, this.path);
    this.loaded = "";
  }

  private refresh() {
    let version: string;
    try {
      const stats = statSync(this.path);
      version = `${stats.mtimeMs}:${stats.size}`;
    } catch {
      this.compiled = [];
      this.loaded = "";
      return;
    }
    if (version === this.loaded) return;
    const parsed: unknown = JSON.parse(readFileSync(this.path, "utf8"));
    if (!Array.isArray(parsed)) throw new Error(`${this.path} must hold a list of {"from", "to"} rules.`);
    // A broken rule in a hand-edited file is skipped, so the others keep working
    this.compiled = parsed.flatMap((entry) => {
      if (typeof entry?.from !== "string" || typeof entry?.to !== "string") return [];
      try {
        return [compile({ from: entry.from, to: entry.to })];
      } catch (error) {
        console.error((error as Error).message);
        return [];
      }
    });
    this.loaded = version;
  }
}

function same(a: string, b: string): boolean {
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}

/** How a rule reads in a list: `air pods → AirPods`, with line breaks shown as ⏎ */
export function describe(rule: Rule): string {
  const to = rule.to === "" ? "(delete)" : rule.to.replace(/\n/g, " ⏎ ");
  return `${rule.from} → ${to}`;
}
