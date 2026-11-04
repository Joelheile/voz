import { Database } from "bun:sqlite";
import type { ExtensionAPI, ScreenText } from "voz";

// Reply's own memory of your screen: the window in front every few seconds, kept in ~/.voz/data/voz-reply for 30 days.
// Voz only lends the read. Nothing leaves your Mac unless a reply sends the matching parts to your AI model.

const every = 5_000;
const mergeWindow = 5 * 60_000;
const keep = 30 * 86_400_000;
const maxText = 20_000;
const maxResults = 50;

export type Seen = {
  app: string;
  window: string;
  thread?: string;
  text: string;
  at: number;
};
export type MemoryQuery = {
  query?: string;
  thread?: string;
  since?: number;
  limit?: number;
};
export type Memory = ReturnType<typeof openMemory>;

type Row = {
  app: string;
  window: string;
  thread: string | null;
  text: string;
  at: number;
};

export function openMemory(path: string) {
  const db = new Database(path, { create: true });
  db.run("PRAGMA journal_mode = WAL");
  db.run(
    "CREATE TABLE IF NOT EXISTS seen (id INTEGER PRIMARY KEY, app TEXT NOT NULL, window TEXT NOT NULL, thread TEXT, text TEXT NOT NULL, at INTEGER NOT NULL)",
  );
  db.run("CREATE INDEX IF NOT EXISTS seen_window ON seen(app, window, at)");
  db.run("CREATE INDEX IF NOT EXISTS seen_thread ON seen(thread, at)");
  db.run(
    "CREATE VIRTUAL TABLE IF NOT EXISTS seen_text USING fts5(window, text, content='seen', content_rowid='id', tokenize='unicode61 remove_diacritics 2')",
  );
  db.run(
    "CREATE TRIGGER IF NOT EXISTS seen_ai AFTER INSERT ON seen BEGIN INSERT INTO seen_text(rowid, window, text) VALUES (new.id, new.window, new.text); END",
  );
  db.run(
    "CREATE TRIGGER IF NOT EXISTS seen_ad AFTER DELETE ON seen BEGIN INSERT INTO seen_text(seen_text, rowid, window, text) VALUES ('delete', old.id, old.window, old.text); END",
  );
  db.run(
    "CREATE TRIGGER IF NOT EXISTS seen_au AFTER UPDATE ON seen BEGIN INSERT INTO seen_text(seen_text, rowid, window, text) VALUES ('delete', old.id, old.window, old.text); INSERT INTO seen_text(rowid, window, text) VALUES (new.id, new.window, new.text); END",
  );

  // Within a few minutes of the last capture of the same window, the new lines join that capture
  function save(screen: ScreenText, at = Date.now()) {
    if (!screen.text.trim()) return;
    const last = db
      .query(
        "SELECT id, text FROM seen WHERE app = ? AND window = ? AND at >= ? ORDER BY at DESC LIMIT 1",
      )
      .get(screen.app, screen.window, at - mergeWindow) as {
      id: number;
      text: string;
    } | null;
    if (last) {
      db.run(
        "UPDATE seen SET text = ?, at = ?, thread = coalesce(?, thread) WHERE id = ?",
        [merge(last.text, screen.text), at, screen.thread ?? null, last.id],
      );
      return;
    }
    db.run(
      "INSERT INTO seen (app, window, thread, text, at) VALUES (?, ?, ?, ?, ?)",
      [
        screen.app,
        screen.window,
        screen.thread ?? null,
        screen.text.slice(-maxText),
        at,
      ],
    );
    db.run("DELETE FROM seen WHERE at < ?", [at - keep]);
  }

  // With a query, captures with any of its words, best first, cut to the part that matches. Without one, the newest, whole.
  function search({
    query,
    thread,
    since,
    limit = 20,
  }: MemoryQuery = {}): Seen[] {
    const filters: string[] = [];
    const params: (string | number)[] = [];
    if (thread) filters.push("seen.thread = ?"), params.push(thread);
    if (since !== undefined) filters.push("seen.at >= ?"), params.push(since);
    const count = Math.max(0, Math.min(Math.floor(limit), maxResults));
    const match = query === undefined ? undefined : matchExpression(query);
    if (query !== undefined && !match) return [];
    const rows = match
      ? db
          .query(
            `SELECT seen.app, seen.window, seen.thread, seen.at, snippet(seen_text, 1, '', '', '…', 48) AS text
                  FROM seen_text JOIN seen ON seen.id = seen_text.rowid
                  WHERE ${["seen_text MATCH ?", ...filters].join(" AND ")}
                  ORDER BY bm25(seen_text, 2.0, 1.0) LIMIT ${count}`,
          )
          .all(match, ...params)
      : db
          .query(
            `SELECT app, window, thread, at, text FROM seen ${filters.length ? `WHERE ${filters.join(" AND ")}` : ""} ORDER BY at DESC LIMIT ${count}`,
          )
          .all(...params);
    return (rows as Row[]).map(({ thread, ...row }) =>
      thread ? { ...row, thread } : row,
    );
  }

  // Trigger rows count as changes too, so this counts first
  function forget() {
    const { count } = db.query("SELECT count(*) AS count FROM seen").get() as { count: number };
    db.run("DELETE FROM seen");
    return count;
  }

  return { save, search, forget };
}

// Reads the window in front every few seconds while Reply is installed, except in the apps you skip. Older Voz can't read the screen.
export function watchScreen(voz: ExtensionAPI, memory: Memory, skip: string[]) {
  if (!voz.screen) return;
  let last = "";
  let reading = false;
  setInterval(async () => {
    if (reading) return;
    reading = true;
    try {
      const screen = await voz.screen();
      const key = screen && `${screen.app}\n${screen.window}\n${screen.text}`;
      if (screen && key !== last && !isSkipped(screen.app, skip)) {
        memory.save(screen);
        last = key!;
      }
    } catch {
      // A window that can't be read is skipped. The next one may work.
    } finally {
      reading = false;
    }
  }, every);
}

// "Messages, whatsapp" skips Messages and WhatsApp
export function skipList(setting: string) {
  return setting.split(",").map((app) => app.trim().toLowerCase()).filter(Boolean);
}

const isSkipped = (app: string, skip: string[]) => skip.includes(app.toLowerCase());

// Keeps the new text whole and puts lines that scrolled away above it, as they were on screen
export function merge(old: string, now: string) {
  const current = new Set(now.split("\n"));
  const gone = old.split("\n").filter((line) => !current.has(line));
  return (gone.length ? `${gone.join("\n")}\n${now}` : now).slice(-maxText);
}

// Any word matches, so a search for several words finds captures with some of them, best first
export function matchExpression(query: string) {
  const words = query.toLowerCase().match(/[\p{L}\p{N}]{2,}/gu) ?? [];
  return (
    [...new Set(words)]
      .sort()
      .map((word) => `"${word}"`)
      .join(" OR ") || undefined
  );
}
