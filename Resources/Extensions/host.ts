import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
} from "node:fs";
import { AsyncLocalStorage } from "node:async_hooks";
import { EventEmitter } from "node:events";
import { basename, extname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import type {
  Action,
  AfterInsertEvent,
  AudioDropEvent,
  Awaitable,
  App,
  BeforeCleanupEvent,
  BeforeCleanupResult,
  BeforeInsertEvent,
  BeforeInsertResult,
  CleanupModel,
  CleanupStep,
  CommandEvent,
  CommandOptions,
  Context,
  GenerateRequest,
  Generated,
  Extension,
  ExtensionAPI,
  RecordingEvent,
  Schema,
  Setting,
  SettingsValues,
  SettingsSchema,
  SpeechModel,
  TranscribeOptions,
  Transcript,
} from "./voz.d.ts";

type Launch = {
  home: string;
  settings: string;
  extensionsDirectory: string;
  packages: string[];
};
type EventName = "beforeCleanup" | "beforeInsert" | "recording" | "afterInsert" | "audioDrop";
type HandlerResult = BeforeInsertResult | BeforeCleanupResult;
type HookPayload = {
  beforeCleanup: BeforeCleanupEvent;
  beforeInsert: BeforeInsertEvent;
  recording: RecordingEvent;
  afterInsert: AfterInsertEvent;
  audioDrop: AudioDropEvent;
};
type Handler = {
  extension: string;
  run: (event: object, ctx: Context) => HandlerResult | Promise<HandlerResult>;
};
type CommandPosition = NonNullable<CommandOptions["at"]>;
type Command = {
  extension: string;
  phrase: string;
  at: CommandPosition;
  run: (event: CommandEvent, ctx: Context) => void | Promise<void>;
};
type CleanupRequest = BeforeCleanupEvent & { app: App };
type InsertRequest = BeforeInsertEvent & { app: App };
type EmitRequest = { event: EventName; payload: object; app: App };
type CommandRequest = CommandEvent & { phrase: string; at: CommandPosition; app: App };
type WireSchema = {
  type: Schema["type"];
  description?: string;
  enum?: readonly string[];
  items?: WireSchema;
  properties?: { name: string; schema: WireSchema; optional: boolean }[];
};
type PendingCall = { resolve: (value: object) => void; reject: (error: Error) => void };
type CallReply = { call: number; json?: string; error?: string };
type TranscribeRequest = { model: string; path: string; seconds: number; app: App };
type CleanRequest = { model: string; text: string; prompt: string; app: App };
type StepRequest = { step: string; text: string; app: App };
type ActionRequest = { action: string; app: App };
type Component = { id: string; name: string };
type Entry = { name: string; path?: string; requires?: number };
type LoadError = { extension: string; message: string };
type Request = { id?: number; method: string; params: never; deadline: number };
type RequestScope = { id?: number; deadline: number; active: boolean };
const requestScope = new AsyncLocalStorage<RequestScope>();
type Config = Record<string, string | number | boolean>;
type SettingsFile = {
  disabled?: string[];
  config?: Record<string, Config>;
};
type PackageManifest = {
  name?: string;
  voz?: { apiVersion?: number; extensions?: string[] };
};

class Registration {
  private active = true;
  private tracking = true;
  private undo: (() => void)[] = [];

  track(undo: () => void) {
    if (!this.active) throw new Error("Extension initialization already failed");
    if (this.tracking) this.undo.push(undo);
  }

  commit() {
    this.tracking = false;
    this.undo = [];
  }

  rollback() {
    this.active = false;
    for (const undo of this.undo.reverse()) undo();
    this.undo = [];
  }
}

const apiVersion = 3;
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
  "audioDrop",
];
const handlers = new Map<EventName, Handler[]>();
const commands = new Map<string, Command>();
const speechModels = new Map<string, SpeechModel>();
const cleanupModels = new Map<string, CleanupModel>();
const cleanupSteps = new Map<string, CleanupStep>();
const actions = new Map<string, Action & { extension: string }>();
const calls = new Map<number, PendingCall>();
let lastCall = 0;
const settingsSchemas = new Map<string, SettingsSchema>();
const loaded: string[] = [];
const bus = new EventEmitter();
const errors: LoadError[] = [];

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
  const scope = requestScope.getStore();
  const isLive = () => scope?.active === true && Date.now() < scope.deadline;
  const action = (method: string, params: { text: string } | { key: string }) => {
    if (!isLive()) return;
    send({ method, params, requestID: scope!.id });
  };
  return {
    app,
    insert: (text) => action("insert", { text }),
    press: (key) => action("press", { key }),
    notify: (text) => action("notify", { text }),
    generate: (request) => {
      if (!isLive()) return Promise.reject(new Error("generate only works while a handler runs"));
      return generate(request, scope!);
    },
    transcribe: (path, options) => {
      if (!isLive()) return Promise.reject(new Error("transcribe only works while a handler runs"));
      return transcribeFile(path, options, scope!);
    },
  };
}

function wireSchema(schema: Schema): WireSchema {
  const { type, description } = schema;
  switch (schema.type) {
    case "object": {
      const required = schema.required ?? [];
      const unknown = required.find((name) => !Object.hasOwn(schema.properties, name));
      if (unknown !== undefined) throw new Error(`Required property "${unknown}" is not in properties`);
      return {
        type,
        description,
        properties: Object.entries(schema.properties).map(([name, property]) => ({
          name,
          schema: wireSchema(property),
          optional: !required.includes(name),
        })),
      };
    }
    case "array":
      return { type, description, items: wireSchema(schema.items) };
    case "string":
      return { type, description, enum: schema.enum };
    case "number":
    case "integer":
    case "boolean":
      return { type, description };
    default:
      throw new Error(`Unsupported schema type "${type}"`);
  }
}

function generate<S extends Schema>(request: GenerateRequest<S>, scope: RequestScope) {
  const params = { prompt: request.prompt, instructions: request.instructions, schema: wireSchema(request.schema) };
  return callSwift("generate", params, scope, "The on-device model ran out of time") as Promise<Generated<S>>;
}

function transcribeFile(path: string, options: TranscribeOptions | undefined, scope: RequestScope) {
  const params = { path, speakers: options?.speakers ?? false };
  return callSwift("transcribeFile", params, scope, "Transcribing the file ran out of time") as Promise<Transcript>;
}

function callSwift(method: string, params: object, scope: RequestScope, timeoutMessage: string) {
  const call = ++lastCall;
  return new Promise<object>((resolve, reject) => {
    const timer = setTimeout(() => settle({ call, error: timeoutMessage }), scope.deadline - Date.now());
    calls.set(call, {
      resolve: (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      reject: (error) => {
        clearTimeout(timer);
        reject(error);
      },
    });
    send({ method, params: { ...params, call, deadline: scope.deadline }, requestID: scope.id });
  });
}

function settle({ call, json, error }: CallReply) {
  const pending = calls.get(call);
  if (!pending) return;
  calls.delete(call);
  if (json === undefined) pending.reject(new Error(error ?? `Voz call ${call} failed`));
  else pending.resolve(JSON.parse(json));
}

function register<T extends Component>(
  registry: Map<string, T>,
  kind: string,
  extension: string,
  component: T,
  registration: Registration,
) {
  if (!component.id || !component.name)
    throw new Error(`A ${kind} needs an id and a name`);
  const id = `${extension}/${component.id}`;
  setRegistered(registry, id, { ...component, id }, registration);
}

function setRegistered<Key, Value>(registry: Map<Key, Value>, key: Key, value: Value, registration: Registration) {
  const previous = registry.get(key);
  registration.track(() => {
    if (registry.get(key) !== value) return;
    if (previous === undefined) registry.delete(key);
    else registry.set(key, previous);
  });
  registry.set(key, value);
}

function components(registry: Map<string, Component>): Component[] {
  return [...registry.values()].map(({ id, name }) => ({ id, name }));
}

function find<T>(registry: Map<string, T>, kind: string, id: string): T {
  const component = registry.get(id);
  if (!component) throw new Error(`No ${kind} "${id}"`);
  return component;
}

function checkSetting(key: string, setting: Setting) {
  if (!["string", "number", "boolean"].includes(setting.type))
    throw new Error(`Setting "${key}" needs type "string", "number" or "boolean"`);
  if (!setting.title) throw new Error(`Setting "${key}" needs a title`);
  if (typeof setting.default !== setting.type)
    throw new Error(`Setting "${key}" needs a ${setting.type} default`);
}

function settingValue(setting: Setting, value: unknown) {
  if (typeof value !== setting.type) return setting.default;
  if (setting.type === "string" && setting.options && !setting.options.includes(value as string))
    return setting.default;
  return value;
}

function readJSON<Value>(path: string): Value | undefined {
  return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) as Value : undefined;
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
  const manifest = readJSON<PackageManifest>(join(directory, "package.json")) ?? {};
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

function api(name: string, config: Config, registration: Registration): ExtensionAPI {
  const data = join(launch.home, "data", name);
  mkdirSync(data, { recursive: true });
  return {
    name,
    paths: { data },
    on<Event extends EventName>(
      event: Event,
      handler: (payload: HookPayload[Event], ctx: Context) => Awaitable<HandlerResult>,
    ) {
      if (!eventNames.includes(event))
        throw new Error(`Unknown event "${event}"`);
      const registered: Handler = {
        extension: name,
        run: (payload, ctx) => handler(payload as HookPayload[Event], ctx),
      };
      registration.track(() => {
        const remaining = (handlers.get(event) ?? []).filter((item) => item !== registered);
        if (remaining.length) handlers.set(event, remaining);
        else handlers.delete(event);
      });
      handlers.set(event, [...(handlers.get(event) ?? []), registered]);
    },
    registerCommand(phrase, handler, options) {
      const at = options?.at ?? "end";
      if (at !== "start" && at !== "end") throw new Error(`Command "${phrase}" needs at: "start" or "end"`);
      const key = commandKey(phrase, at);
      const existing = commands.get(key);
      if (existing)
        log(`${name} replaces command "${phrase}" from ${existing.extension}`);
      setRegistered(commands, key, { extension: name, phrase, at, run: handler }, registration);
    },
    registerSpeechModel: (model) =>
      register(speechModels, "speech model", name, model, registration),
    registerCleanupModel: (model) =>
      register(cleanupModels, "cleanup model", name, model, registration),
    registerCleanupStep: (step) =>
      register(cleanupSteps, "cleanup step", name, step, registration),
    registerAction: (action) => register(actions, "action", name, { ...action, extension: name }, registration),
    settings<Schema extends SettingsSchema>(schema: Schema) {
      for (const [key, setting] of Object.entries(schema)) checkSetting(key, setting);
      setRegistered(settingsSchemas, name, schema, registration);
      return Object.fromEntries(
        Object.entries(schema).map(([key, setting]) => [key, settingValue(setting, config[key])]),
      ) as SettingsValues<Schema>;
    },
  };
}

async function load() {
  const settings = readJSON<SettingsFile>(launch.settings) ?? {};
  const entries = [
    ...looseEntries(launch.extensionsDirectory),
    ...launch.packages.flatMap(packageEntries),
  ];
  const disabled: string[] = settings.disabled ?? [];
  for (const entry of entries) {
    if (isDisabled(entry.name, disabled)) continue;
    const registration = new Registration();
    try {
      await withinLoadTimeout(loadEntry(entry, settings.config?.[entry.name], registration));
      registration.commit();
      loaded.push(entry.name);
    } catch (error) {
      registration.rollback();
      errors.push({ extension: entry.name, message: describe(error) });
    }
  }
}

async function loadEntry(entry: Entry, config: Config = {}, registration: Registration) {
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
  const current = api(entry.name, config, registration);
  await module.default((entry.requires ?? 1) < 2 ? withApi1Removals(current, config, registration) : current);
}

function withApi1Removals(current: ExtensionAPI, config: Config, registration: Registration) {
  return {
    ...current,
    config,
    paths: { ...current.paths, home: launch.home },
    log: (message: string) => log(`[${current.name}] ${message}`),
    events: {
      on(event: string, handler: (payload: unknown) => void) {
        registration.track(() => bus.off(event, handler));
        bus.on(event, handler);
      },
      emit: (event: string, payload: unknown) => bus.emit(event, payload),
    },
    on(event: EventName, handler: Handler["run"]) {
      const handled: Handler["run"] = async (payload, ctx) => {
        const result = await handler(payload, ctx);
        return result && "handled" in result && result.handled === true ? { text: "" } : result;
      };
      current.on(event as never, (event === "beforeInsert" ? handled : handler) as never);
    },
  };
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
    if (Date.now() >= requestScope.getStore()!.deadline) break;
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
    if (Date.now() >= requestScope.getStore()!.deadline) break;
    try {
      const result = (await handler.run({ text, raw }, ctx)) as BeforeInsertResult;
      if (result && typeof result.text === "string") text = result.text;
      if (!text) break;
    } catch (error) {
      log(`${handler.extension} beforeInsert failed: ${describe(error)}`);
    }
  }
  return { text };
}

async function emit({ event, payload, app }: EmitRequest) {
  const ctx = context(app);
  let failed = false;
  await Promise.all(
    (handlers.get(event) ?? []).map(async (handler) => {
      try {
        await handler.run(payload, ctx);
      } catch (error) {
        failed = true;
        log(`${handler.extension} ${event} failed: ${describe(error)}`);
      }
    }),
  );
  return { failed };
}

function commandKey(phrase: string, at: CommandPosition) {
  return `${at}:${phrase.trim().toLowerCase()}`;
}

async function command({ phrase, at, text, app }: CommandRequest) {
  const match = commands.get(commandKey(phrase, at));
  if (!match) return { handled: false };
  await match.run({ text }, context(app));
  return { handled: true };
}

async function transcribe({ model, path, seconds, app }: TranscribeRequest) {
  const result = await find(speechModels, "speech model", model).transcribe(
    { path, seconds },
    context(app),
  );
  if (!result || typeof result.text !== "string") throw new Error("Speech model must return string text");
  return { text: result.text };
}

async function clean({ model, text, prompt, app }: CleanRequest) {
  const result = await find(cleanupModels, "cleanup model", model).clean(
    { text, prompt },
    context(app),
  );
  if (!result || typeof result.text !== "string") throw new Error("Cleanup model must return string text");
  return { text: result.text };
}

async function cleanupStep({ step, text, app }: StepRequest) {
  const result = await find(cleanupSteps, "cleanup step", step).run(
    { text },
    context(app),
  );
  return { text: result && typeof result.text === "string" ? result.text : text };
}

async function action({ action, app }: ActionRequest) {
  await find(actions, "action", action).run(context(app));
  return {};
}

const methods = {
  beforeCleanup,
  action,
  beforeInsert,
  clean,
  cleanupStep,
  command,
  transcribe,
  emit,
  ping: async () => ({}),
} satisfies Record<string, (params: never) => Promise<object>>;

function parseRequest(line: string): Request | undefined {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch (error) {
    log(`Invalid request: ${describe(error)}`);
    return;
  }
  if (!value || typeof value !== "object" || !("method" in value) || typeof value.method !== "string") {
    log("Invalid request: method must be a string");
    return;
  }
  const id = "id" in value && typeof value.id === "number" ? value.id : undefined;
  const params = "params" in value ? value.params : {};
  if (!("deadline" in value) || typeof value.deadline !== "number" || !Number.isFinite(value.deadline)) {
    log("Invalid request: deadline must be a finite number");
    return;
  }
  return { id, method: value.method, params: params as never, deadline: value.deadline };
}

await load();
send({
  method: "ready",
  params: {
    extensions: loaded,
    events: [...handlers.keys()],
    commands: [...commands.values()].map(({ extension, phrase, at }) => ({ extension, phrase, at })),
    speechModels: components(speechModels),
    cleanupModels: components(cleanupModels),
    cleanupSteps: components(cleanupSteps),
    actions: [...actions.values()].map(({ id, name, hotkey, extension }) => ({ id, name, hotkey, extension })),
    settings: [...settingsSchemas].map(([extension, schema]) => ({
      extension,
      fields: Object.entries(schema).map(([key, setting]) => ({ key, ...setting })),
    })),
    errors,
  },
});

for await (const line of createInterface({ input: process.stdin })) {
  if (!line.trim()) continue;
  const request = parseRequest(line);
  if (!request) continue;
  if (request.method === "generated" || request.method === "transcribedFile") {
    settle(request.params);
    continue;
  }
  const method = Object.hasOwn(methods, request.method)
    ? methods[request.method as keyof typeof methods]
    : undefined;
  if (!method) {
    send({ id: request.id, error: `Unknown method ${request.method}` });
    continue;
  }
  const scope: RequestScope = { id: request.id, deadline: request.deadline, active: true };
  requestScope.run(scope, async () => {
    try {
      if (Date.now() >= scope.deadline) throw new Error("Request expired");
      send({ id: request.id, result: await method(request.params) });
    } catch (error) {
      send({ id: request.id, error: describe(error) });
    } finally {
      scope.active = false;
    }
  });
}
process.exit(0);
