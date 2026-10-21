export type App = { bundleID?: string; name?: string };

export type Paths = { home: string; data: string };

export type Context = {
  app: App;
  insert(text: string): void;
  press(key: string): void;
  notify(text: string): void;
};

export type BeforeCleanupEvent = { prompt: string };
export type BeforeCleanupResult = { prompt: string } | void;
export type BeforeInsertEvent = { text: string; raw: string };
export type BeforeInsertResult = { text: string } | { handled: true } | void;
export type CommandEvent = { text: string };
export type RecordingEvent = { path: string; seconds: number };
export type AfterInsertEvent = { text: string; raw: string };
export type TranscribeEvent = { path: string; seconds: number };
export type CleanEvent = { text: string; prompt: string };
export type CleanupStepEvent = { text: string };

export type SpeechModel = {
  id: string;
  name: string;
  transcribe(
    event: TranscribeEvent,
    ctx: Context,
  ): Awaitable<{ text: string }>;
};

export type CleanupModel = {
  id: string;
  name: string;
  clean(event: CleanEvent, ctx: Context): Awaitable<{ text: string }>;
};

export type CleanupStep = {
  id: string;
  name: string;
  run(event: CleanupStepEvent, ctx: Context): Awaitable<{ text: string } | void>;
};

type Awaitable<T> = T | Promise<T>;

export type EventBus = {
  on<T>(name: string, handler: (data: T) => void): void;
  emit<T>(name: string, data: T): void;
};

export type ExtensionAPI = {
  name: string;
  config: Record<string, string | number | boolean>;
  paths: Paths;
  events: EventBus;
  on(
    event: "beforeCleanup",
    handler: (
      event: BeforeCleanupEvent,
      ctx: Context,
    ) => Awaitable<BeforeCleanupResult>,
  ): void;
  on(
    event: "beforeInsert",
    handler: (
      event: BeforeInsertEvent,
      ctx: Context,
    ) => Awaitable<BeforeInsertResult>,
  ): void;
  on(
    event: "recording",
    handler: (event: RecordingEvent, ctx: Context) => Awaitable<void>,
  ): void;
  on(
    event: "afterInsert",
    handler: (event: AfterInsertEvent, ctx: Context) => Awaitable<void>,
  ): void;
  registerCommand(
    phrase: string,
    handler: (event: CommandEvent, ctx: Context) => Awaitable<void>,
  ): void;
  registerSpeechModel(model: SpeechModel): void;
  registerCleanupModel(model: CleanupModel): void;
  registerCleanupStep(step: CleanupStep): void;
  log(message: string): void;
};

export type Extension = (voz: ExtensionAPI) => Awaitable<void>;

export const apiVersion: 1;

export function defineExtension(extension: Extension): Extension;
