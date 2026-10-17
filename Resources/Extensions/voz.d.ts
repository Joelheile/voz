export type App = { bundleID?: string; name?: string };

export type Paths = { home: string; data: string };

export type Context = {
  app: App;
  insert(text: string): void;
  press(key: string): void;
};

export type BeforeInsertEvent = { text: string; raw: string };
export type BeforeInsertResult = { text: string } | { handled: true } | void;
export type CommandEvent = { text: string };
export type RecordingEvent = { path: string; seconds: number };
export type AfterInsertEvent = { text: string; raw: string };

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
  log(message: string): void;
};

export type Extension = (voz: ExtensionAPI) => Awaitable<void>;

export function defineExtension(extension: Extension): Extension;
