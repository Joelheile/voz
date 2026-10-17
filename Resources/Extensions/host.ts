import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { EventEmitter } from "node:events";
import { basename, extname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import type {
  App,
  BeforeInsertEvent,
  BeforeInsertResult,
  CommandEvent,
  Context,
  Extension,
  ExtensionAPI,
} from "./voz.d.ts";

type Launch = {
  home: string;
  settings: string;
  extensionsDirectory: string;
  packages: string[];
};
type InsertHandler = {
  extension: string;
  run: (
    event: BeforeInsertEvent,
    ctx: Context,
  ) => BeforeInsertResult | Promise<BeforeInsertResult>;
};
type Command = {
  extension: string;
  phrase: string;
  run: (event: CommandEvent, ctx: Context) => void | Promise<void>;
};
type InsertRequest = BeforeInsertEvent & { app: App };
type CommandRequest = CommandEvent & { phrase: string; app: App };

const send = (message: object) =>
  process.stdout.write(JSON.stringify(message) + "\n");
const log = (text: string) => send({ method: "log", params: { text } });
const describe = (error: unknown) =>
  error instanceof Error ? error.stack ?? error.message : String(error);

console.log =
  console.info =
  console.debug =
    (...parts: unknown[]) => log(parts.map(String).join(" "));

const launch: Launch = JSON.parse(process.argv[2]);
const insertHandlers: InsertHandler[] = [];
const commands = new Map<string, Command>();
const loaded: string[] = [];
const errors: string[] = [];
const bus = new EventEmitter();

Bun.plugin({
  name: "voz",
  setup(build) {
    build.module("voz", () => ({
      exports: { defineExtension: (extension: Extension) => extension },
      loader: "object",
    }));
  },
});

function installTypes() {
  const directory = join(launch.home, "node_modules", "voz");
  mkdirSync(directory, { recursive: true });
  copyFileSync(join(import.meta.dir, "voz.d.ts"), join(directory, "index.d.ts"));
  writeFileSync(
    join(directory, "package.json"),
    JSON.stringify({ name: "voz", private: true, types: "index.d.ts" }),
  );
}

function context(app: App): Context {
  return {
    app,
    insert: (text) => send({ method: "insert", params: { text } }),
    press: (key) => send({ method: "press", params: { key } }),
  };
}

function readJSON(path: string): any {
  return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : undefined;
}

function entryIn(directory: string): string | undefined {
  return ["index.ts", "index.js"]
    .map((file) => join(directory, file))
    .find(existsSync);
}

function looseEntries(directory: string): { name: string; path: string }[] {
  if (!existsSync(directory)) return [];
  return readdirSync(directory)
    .filter((file) => !file.startsWith("."))
    .sort()
    .flatMap((file) => {
      const path = join(directory, file);
      if (statSync(path).isDirectory()) {
        const entry = entryIn(path);
        return entry ? [{ name: file, path: entry }] : [];
      }
      return [".ts", ".js"].includes(extname(file))
        ? [{ name: basename(file, extname(file)), path }]
        : [];
    });
}

function packageEntries(directory: string): { name: string; path: string }[] {
  const manifest = readJSON(join(directory, "package.json")) ?? {};
  const name: string = manifest.name ?? basename(directory);
  const declared: string[] | undefined = manifest.voz?.extensions;
  if (declared)
    return declared.map((path, index) => ({
      name: declared.length > 1 ? `${name}/${index}` : name,
      path: resolve(directory, path),
    }));
  const folder = join(directory, "extensions");
  if (existsSync(folder))
    return looseEntries(folder).map((entry) => ({
      ...entry,
      name: `${name}/${entry.name}`,
    }));
  const entry = entryIn(directory);
  return entry ? [{ name, path: entry }] : [];
}

function api(name: string, config: ExtensionAPI["config"]): ExtensionAPI {
  const data = join(launch.home, "data", name);
  mkdirSync(data, { recursive: true });
  return {
    name,
    config,
    paths: { home: launch.home, data },
    events: {
      on: (event, handler) => bus.on(event, handler),
      emit: (event, payload) => bus.emit(event, payload),
    },
    on(event, handler) {
      if (event !== "beforeInsert") throw new Error(`Unknown event "${event}"`);
      insertHandlers.push({ extension: name, run: handler });
    },
    registerCommand(phrase, handler) {
      const key = phrase.trim().toLowerCase();
      const existing = commands.get(key);
      if (existing)
        log(`${name} replaces command "${phrase}" from ${existing.extension}`);
      commands.set(key, { extension: name, phrase, run: handler });
    },
    log: (message) => log(`[${name}] ${message}`),
  };
}

async function load() {
  const settings = readJSON(launch.settings) ?? {};
  const entries = [
    ...looseEntries(launch.extensionsDirectory),
    ...launch.packages.flatMap(packageEntries),
  ];
  for (const entry of entries) {
    try {
      const module = await import(entry.path);
      if (typeof module.default !== "function")
        throw new Error("default export is not a function");
      await module.default(
        api(entry.name, settings.config?.[entry.name] ?? {}),
      );
      loaded.push(entry.name);
    } catch (error) {
      errors.push(`${entry.name}: ${describe(error)}`);
    }
  }
}

async function beforeInsert({ text, raw, app }: InsertRequest) {
  const ctx = context(app);
  for (const handler of insertHandlers) {
    try {
      const result = await handler.run({ text, raw }, ctx);
      if (result && "handled" in result) return { text: "" };
      if (result && typeof result.text === "string") text = result.text;
    } catch (error) {
      log(`${handler.extension} beforeInsert failed: ${describe(error)}`);
    }
  }
  return { text };
}

async function command({ phrase, text, app }: CommandRequest) {
  const match = commands.get(phrase.trim().toLowerCase());
  if (!match) return { handled: false };
  await match.run({ text }, context(app));
  return { handled: true };
}

const methods: Record<string, (params: any) => Promise<object>> = {
  beforeInsert,
  command,
  ping: async () => ({}),
};

installTypes();
await load();
send({
  method: "ready",
  params: {
    extensions: loaded,
    events: insertHandlers.length > 0 ? ["beforeInsert"] : [],
    commands: [...commands.values()].map((command) => command.phrase),
    errors,
  },
});

for await (const line of createInterface({ input: process.stdin })) {
  if (!line.trim()) continue;
  const request = JSON.parse(line);
  const method = methods[request.method];
  if (!method) {
    send({ id: request.id, error: `Unknown method ${request.method}` });
    continue;
  }
  method(request.params)
    .then((result) => send({ id: request.id, result }))
    .catch((error) => send({ id: request.id, error: describe(error) }));
}
