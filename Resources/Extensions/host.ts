import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
} from "node:fs";
import { EventEmitter } from "node:events";
import { basename, extname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import type {
  App,
  BeforeCleanupEvent,
  BeforeCleanupResult,
  BeforeInsertEvent,
  BeforeInsertResult,
  CleanupModel,
  CleanupStep,
  CommandEvent,
  Context,
  Extension,
  ExtensionAPI,
  SpeechModel,
} from "./voz.d.ts";

type Launch = {
  home: string;
  settings: string;
  extensionsDirectory: string;
  packages: string[];
};
type EventName = "beforeCleanup" | "beforeInsert" | "recording" | "afterInsert";
type HandlerResult = BeforeInsertResult | BeforeCleanupResult;
type Handler = {
  extension: string;
  run: (event: object, ctx: Context) => HandlerResult | Promise<HandlerResult>;
};
type Command = {
  extension: string;
  phrase: string;
  run: (event: CommandEvent, ctx: Context) => void | Promise<void>;
};
type CleanupRequest = BeforeCleanupEvent & { app: App };
type InsertRequest = BeforeInsertEvent & { app: App };
type EmitRequest = { event: EventName; payload: object; app: App };
type CommandRequest = CommandEvent & { phrase: string; app: App };
type TranscribeRequest = { model: string; path: string; seconds: number; app: App };
type CleanRequest = { model: string; text: string; prompt: string; app: App };
type StepRequest = { step: string; text: string; app: App };
type Component = { id: string; name: string };
type Entry = { name: string; path?: string; requires?: number };
type LoadError = { extension: string; message: string };

const apiVersion = 1;
const loadTimeout = 3000;
const write = process.stdout.write.bind(process.stdout);
const send = (message: object) => write(JSON.stringify(message) + "\n");
const log = (text: string) => send({ method: "log", params: { text } });
const describe = (error: unknown) =>
  error instanceof Error ? error.stack ?? error.message : String(error);

console.log =
  console.info =
  console.debug =
    (...parts: unknown[]) => log(parts.map(String).join(" "));
process.stdout.write = ((chunk: string | Uint8Array) => {
  log(typeof chunk === "string" ? chunk : new TextDecoder().decode(chunk));
  return true;
}) as typeof process.stdout.write;
process.on("unhandledRejection", (error) =>
  log(`Unhandled rejection: ${describe(error)}`),
);

const launch: Launch = JSON.parse(process.argv[2]);
const eventNames: EventName[] = [
  "beforeCleanup",
  "beforeInsert",
  "recording",
  "afterInsert",
];
const handlers = new Map<EventName, Handler[]>();
const commands = new Map<string, Command>();
const speechModels = new Map<string, SpeechModel>();
const cleanupModels = new Map<string, CleanupModel>();
const cleanupSteps = new Map<string, CleanupStep>();
const loaded: string[] = [];
const errors: LoadError[] = [];
const bus = new EventEmitter();

Bun.plugin({
  name: "voz",
  setup(build) {
    build.module("voz", () => ({
      exports: { apiVersion, defineExtension: (extension: Extension) => extension },
      loader: "object",
    }));
  },
});

function context(app: App): Context {
  return {
    app,
    insert: (text) => send({ method: "insert", params: { text } }),
    press: (key) => send({ method: "press", params: { key } }),
    notify: (text) => send({ method: "notify", params: { text } }),
  };
}

function register<T extends Component>(
  registry: Map<string, T>,
  kind: string,
  extension: string,
  component: T,
) {
  if (!component.id || !component.name)
    throw new Error(`A ${kind} needs an id and a name`);
  const id = `${extension}/${component.id}`;
  registry.set(id, { ...component, id });
}

function components(registry: Map<string, Component>): Component[] {
  return [...registry.values()].map(({ id, name }) => ({ id, name }));
}

function find<T>(registry: Map<string, T>, kind: string, id: string): T {
  const component = registry.get(id);
  if (!component) throw new Error(`No ${kind} "${id}"`);
  return component;
}

function readJSON(path: string): any {
  return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : undefined;
}

function entryIn(directory: string): string | undefined {
  return ["index.ts", "index.js"]
    .map((file) => join(directory, file))
    .find(existsSync);
}

function looseEntries(directory: string): Entry[] {
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

function packageEntries(directory: string): Entry[] {
  const manifest = readJSON(join(directory, "package.json")) ?? {};
  const name: string = manifest.name ?? basename(directory);
  const origin = { requires: manifest.voz?.apiVersion };
  const declared: string[] | undefined = manifest.voz?.extensions;
  if (declared)
    return declared.map((path, index) => ({
      ...origin,
      name: declared.length > 1 ? `${name}/${index}` : name,
      path: resolve(directory, path),
    }));
  const folder = join(directory, "extensions");
  if (existsSync(folder))
    return looseEntries(folder).map((entry) => ({
      ...entry,
      ...origin,
      name: `${name}/${entry.name}`,
    }));
  return [{ ...origin, name, path: entryIn(directory) }];
}

function isDisabled(name: string, disabled: string[]) {
  return disabled.some((off) => name === off || name.startsWith(`${off}/`));
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
    on(event: EventName, handler: Handler["run"]) {
      if (!eventNames.includes(event))
        throw new Error(`Unknown event "${event}"`);
      handlers.set(event, [
        ...(handlers.get(event) ?? []),
        { extension: name, run: handler },
      ]);
    },
    registerCommand(phrase, handler) {
      const key = phrase.trim().toLowerCase();
      const existing = commands.get(key);
      if (existing)
        log(`${name} replaces command "${phrase}" from ${existing.extension}`);
      commands.set(key, { extension: name, phrase, run: handler });
    },
    registerSpeechModel: (model) =>
      register(speechModels, "speech model", name, model),
    registerCleanupModel: (model) =>
      register(cleanupModels, "cleanup model", name, model),
    registerCleanupStep: (step) =>
      register(cleanupSteps, "cleanup step", name, step),
    log: (message) => log(`[${name}] ${message}`),
  };
}

async function load() {
  const settings = readJSON(launch.settings) ?? {};
  const entries = [
    ...looseEntries(launch.extensionsDirectory),
    ...launch.packages.flatMap(packageEntries),
  ];
  const disabled: string[] = settings.disabled ?? [];
  for (const entry of entries) {
    if (isDisabled(entry.name, disabled)) continue;
    try {
      await withinLoadTimeout(loadEntry(entry, settings.config?.[entry.name]));
      loaded.push(entry.name);
    } catch (error) {
      errors.push({ extension: entry.name, message: describe(error) });
    }
  }
}

async function loadEntry(entry: Entry, config: ExtensionAPI["config"] = {}) {
  if (!entry.path)
    throw new Error(
      "No entry. Add voz.extensions to package.json, an extensions folder or an index.ts",
    );
  if (entry.requires && entry.requires > apiVersion)
    throw new Error(
      `Needs Voz extension API ${entry.requires}, this Voz has ${apiVersion}. Update Voz.`,
    );
  const module = await import(entry.path);
  if (typeof module.default !== "function")
    throw new Error("default export is not a function");
  await module.default(api(entry.name, config));
}

function withinLoadTimeout(work: Promise<void>): Promise<void> {
  const timeout = new Promise<never>((_, reject) =>
    setTimeout(
      () => reject(new Error(`did not load within ${loadTimeout / 1000} s`)),
      loadTimeout,
    ).unref(),
  );
  return Promise.race([work, timeout]);
}

async function beforeCleanup({ prompt, app }: CleanupRequest) {
  const ctx = context(app);
  for (const handler of handlers.get("beforeCleanup") ?? []) {
    try {
      const result = (await handler.run({ prompt }, ctx)) as BeforeCleanupResult;
      if (result && typeof result.prompt === "string") prompt = result.prompt;
    } catch (error) {
      log(`${handler.extension} beforeCleanup failed: ${describe(error)}`);
    }
  }
  return { prompt };
}

async function beforeInsert({ text, raw, app }: InsertRequest) {
  const ctx = context(app);
  for (const handler of handlers.get("beforeInsert") ?? []) {
    try {
      const result = (await handler.run({ text, raw }, ctx)) as BeforeInsertResult;
      if (result && "handled" in result) return { text: "" };
      if (result && typeof result.text === "string") text = result.text;
    } catch (error) {
      log(`${handler.extension} beforeInsert failed: ${describe(error)}`);
    }
  }
  return { text };
}

async function emit({ event, payload, app }: EmitRequest) {
  const ctx = context(app);
  await Promise.all(
    (handlers.get(event) ?? []).map(async (handler) => {
      try {
        await handler.run(payload, ctx);
      } catch (error) {
        log(`${handler.extension} ${event} failed: ${describe(error)}`);
      }
    }),
  );
  return {};
}

async function command({ phrase, text, app }: CommandRequest) {
  const match = commands.get(phrase.trim().toLowerCase());
  if (!match) return { handled: false };
  await match.run({ text }, context(app));
  return { handled: true };
}

async function transcribe({ model, path, seconds, app }: TranscribeRequest) {
  const result = await find(speechModels, "speech model", model).transcribe(
    { path, seconds },
    context(app),
  );
  return { text: String(result.text) };
}

async function clean({ model, text, prompt, app }: CleanRequest) {
  const result = await find(cleanupModels, "cleanup model", model).clean(
    { text, prompt },
    context(app),
  );
  return { text: String(result.text) };
}

async function cleanupStep({ step, text, app }: StepRequest) {
  const result = await find(cleanupSteps, "cleanup step", step).run(
    { text },
    context(app),
  );
  return { text: result && typeof result.text === "string" ? result.text : text };
}

const methods: Record<string, (params: any) => Promise<object>> = {
  beforeCleanup,
  beforeInsert,
  clean,
  cleanupStep,
  command,
  transcribe,
  emit,
  ping: async () => ({}),
};

await load();
send({
  method: "ready",
  params: {
    extensions: loaded,
    events: [...handlers.keys()],
    commands: [...commands.values()].map((command) => command.phrase),
    speechModels: components(speechModels),
    cleanupModels: components(cleanupModels),
    cleanupSteps: components(cleanupSteps),
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
process.exit(0);
