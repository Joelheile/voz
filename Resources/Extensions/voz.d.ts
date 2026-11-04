/** `website` is the hostname of the focused web page, such as "github.com", in Safari and Chromium browsers. */
export type App = { bundleID?: string; name?: string; website?: string };

export type Paths = { data: string };

export type Schema =
  | { type: "string"; description?: string; enum?: readonly string[] }
  | { type: "number" | "integer" | "boolean"; description?: string }
  | { type: "array"; description?: string; items: Schema }
  | {
      type: "object";
      description?: string;
      properties: Record<string, Schema>;
      required?: readonly string[];
    };

export type Generated<S extends Schema> = S extends {
  type: "string";
  enum: readonly (infer Choice)[];
}
  ? Choice
  : S extends { type: "string" }
    ? string
    : S extends { type: "number" | "integer" }
      ? number
      : S extends { type: "boolean" }
        ? boolean
        : S extends { type: "array"; items: infer Item extends Schema }
          ? Generated<Item>[]
          : S extends {
                type: "object";
                properties: infer Properties extends Record<string, Schema>;
              }
            ? {
                [Key in keyof Properties as Key extends RequiredKeys<S>
                  ? Key
                  : never]: Generated<Properties[Key]>;
              } & {
                [Key in keyof Properties as Key extends RequiredKeys<S>
                  ? never
                  : Key]?: Generated<Properties[Key]>;
              }
            : never;

export type ObjectSchema = Extract<Schema, { type: "object" }>;

type RequiredKeys<S> = S extends { required: readonly (infer Key)[] }
  ? Key
  : never;

export type GenerateRequest<S extends Schema> = {
  prompt: string;
  instructions?: string;
  schema: S;
  /**
   * A tier, which runs the newest model of that tier on the user's account, or an exact ID from `ctx.models()`.
   * An ID from another provider runs as the same tier, so `claude-opus-5-5` runs GPT-6.1 Sol for a ChatGPT user.
   * Apple's on-device model ignores it. Default `balanced`.
   * `on-device` runs Apple's model on the Mac whatever the user picked: free and private, for background work such as learning.
   */
  model?: ModelTier | "on-device" | (string & {});
  /** How long the model thinks first. Default: the least it allows, which suits most writing. */
  effort?: "low" | "medium" | "high";
};

/** `fast`: Haiku or Luna. `balanced`: Sonnet or Terra. `strong`: Opus or Sol. `max`: Fable or Astra. */
export type ModelTier = "fast" | "balanced" | "strong" | "max";
export type ModelInfo = { id: string; name: string; tier?: ModelTier };
/** The models the user's account offers. `tiers` says which model each tier runs right now. */
export type Models = {
  provider: "apple" | "chatgpt" | "claude";
  tiers: Partial<Record<ModelTier, string>>;
  models: ModelInfo[];
};

export type TranscribeOptions = { speakers?: boolean };
export type Turn = {
  speaker: number;
  start: number;
  end: number;
  text: string;
};
export type Transcript = {
  text: string;
  seconds: number;
  speakers: number;
  turns: Turn[];
};
/** `systemAudio` mixes everything the Mac plays, such as a call, into the microphone. `onTranscript` gets the whole transcript so far, a few seconds behind speech. Earlier turns can change. */
export type LiveTranscribeOptions = TranscribeOptions & {
  systemAudio?: boolean;
  onTranscript?(transcript: Transcript): void;
};
export type LiveTranscription = { stop(): Promise<Transcript> };
/** A small note window the user can move. `onChange` gets the full text after the user pauses typing. */
export type NoteOptions = {
  title?: string;
  text?: string;
  onChange?(text: string): void;
};
export type Note = { close(): void };
/** A field the user can edit in `ctx.ask`. A `date` value is milliseconds since 1970. */
export type AskField =
  | { id: string; label: string; type: "text"; value: string }
  | { id: string; label: string; type: "date"; value: number }
  | {
      id: string;
      label: string;
      type: "choice";
      value: string;
      options: string[];
    };
/** The last button is the main one. */
export type AskOptions = {
  title: string;
  fields?: AskField[];
  buttons: string[];
};
/** `null` when the user closes the card. `values` holds each field by `id`. */
export type Answer = {
  button: string;
  values: Record<string, string | number>;
} | null;

/** Offsets count UTF-16 code units, like JavaScript string indexes. */
export type TextRange = { start: number; length: number };
/**
 * The text field that has focus. `before` and `after` hold the text on screen around it, such as the messages above a reply box.
 * `label` is the field's description, title or placeholder. `window` is the window title.
 * `thread` is the conversation the window shows, named after its title without unread counts or the app name. Pass its `id` to `voz.history`.
 */
export type Field = {
  text: string;
  selection: TextRange;
  role: string;
  label?: string;
  window?: string;
  before: string;
  after: string;
  thread?: Thread;
};

export type Thread = { id: string; title: string };

/** `instruction` is what the user asked for, saved with the draft so `voz.history` can show it later. */
export type InsertOptions = { instruction?: string };

/** With `source`, only drafts that extension inserted. Without it, dictations too. `limit` defaults to 20, at most 100. */
export type HistoryQuery = { thread?: string; source?: string; limit?: number };

/**
 * Something the user wrote, newest first. `text` is what ended up in the field: the user's edit when they changed a draft.
 * Drafts also have the extension that wrote them as `source`, the `instruction`, the `input` it replaced, the `output` it inserted, and the `outcome`.
 * `outcome` is `unknown` while Voz still watches the field or when it could not read it.
 */
export type Written = {
  kind: "dictation" | "draft";
  text: string;
  /** Milliseconds since 1970, like `Date.now()` */
  at: number;
  thread?: string;
  source?: string;
  instruction?: string;
  input?: string;
  output?: string;
  outcome?: "unknown" | "kept" | "edited" | "sent" | "removed";
  /** The bundle ID of the app it was written in, when Voz knows the conversation */
  app?: string;
  /** The conversation's title, such as a person or channel, as in `Thread` */
  threadTitle?: string;
};

/**
 * The window in front, read through Accessibility. `text` is what it shows, top to bottom, without password fields, and with keys, tokens,
 * card numbers and IBANs hidden. `thread` is the conversation it shows, as in `Field`.
 */
export type ScreenText = { app: string; window: string; thread?: string; text: string };

export type TransformContext = { app: App };

export type Context = TransformContext & {
  /** Types text into the focused app. Voz saves it as a draft and watches whether the user keeps, edits, sends or removes it. */
  insert(text: string, options?: InsertOptions): void;
  press(key: string): void;
  notify(text: string): void;
  generate<const S extends Schema>(
    request: GenerateRequest<S>,
  ): Promise<Generated<S>>;
  transcribe(path: string, options?: TranscribeOptions): Promise<Transcript>;
  /** Lists the models `generate` can use with the AI model the user picked in Settings. */
  models(): Promise<Models>;
  openNote(note: NoteOptions): Note;
  /** Shows a card under the notch and waits for the user to press a button. The handler's time stops while it waits. */
  ask(options: AskOptions): Promise<Answer>;
  /** Reads the focused text field through Accessibility. `null` for password fields, when no text field has focus, or when the app hides its text. */
  field(): Promise<Field | null>;
  /** Selects a range in the focused text field, so `insert` replaces it. `false` when the app refuses. */
  select(range: TextRange): Promise<boolean>;
  /**
   * Shows a working state in the notch while `run` runs, then a checkmark, or a shake when it throws. The handler's time stops meanwhile.
   * Esc or the X in the notch aborts `signal` and resolves `undefined` right away. Pass `signal` to `fetch` so the request stops too.
   */
  busy<T>(run: (signal: AbortSignal) => Promise<T>): Promise<T | undefined>;
};

/** `light` only removes fillers and fixes punctuation. `heavy` also applies the prompt, self-corrections, numbers and lists. */
export type CleanupMode = "light" | "heavy";
export type BeforeCleanupEvent = { prompt: string; mode: CleanupMode };
export type BeforeCleanupResult = {
  prompt?: string;
  mode?: CleanupMode;
} | void;
export type BeforeInsertEvent = { text: string; raw: string };
export type BeforeInsertResult = { text: string } | void;
export type CommandEvent = { text: string };
export type RecordingEvent = { path: string; seconds: number };
export type AfterInsertEvent = { text: string; raw: string };
export type AudioDropEvent = { path: string };
export type TranscribeEvent = { path: string; seconds: number };
export type CleanEvent = { text: string; prompt: string };
export type CleanupStepEvent = { text: string };

export type SpeechModel = {
  id: string;
  name: string;
  transcribe(event: TranscribeEvent, ctx: Context): Awaitable<{ text: string }>;
};

export type CleanupModel = {
  id: string;
  name: string;
  clean(event: CleanEvent, ctx: Context): Awaitable<{ text: string }>;
};

export type CleanupStep = {
  id: string;
  name: string;
  run(
    event: CleanupStepEvent,
    ctx: TransformContext,
  ): Awaitable<{ text: string } | void>;
};

export type Command = {
  phrase: string;
  /** "anywhere" runs when the phrase is any whole words of the dictation and passes the whole text. Since API 7. */
  at?: "start" | "end" | "anywhere";
  run(event: CommandEvent, ctx: Context): Awaitable<void>;
};

export type Action = {
  id: string;
  name: string;
  /**
   * A chord such as "ctrl+opt+e", or a modifier key tapped on its own: "rightopt", "leftopt", "rightcmd", "leftcmd",
   * "rightshift", "leftshift", "rightctrl", "leftctrl" or "fn". Actions can share a hotkey when `when` tells them apart.
   */
  hotkey?: string;
  /** "selection" runs this action only when text is selected. Another action on the same hotkey without `when` runs otherwise. */
  when?: "selection";
  hidden?: boolean;
  run(ctx: Context): Awaitable<void>;
};

/**
 * Agents and the terminal call a tool as `voz <extension> <id>`, and AI apps see it over MCP. Return JSON.
 * Group tools with `/` in the id: `issues/create` runs as `voz jira issues create`.
 */
export type Tool<S extends ObjectSchema = ObjectSchema> = {
  id: string;
  description: string;
  /** Leave out when the tool takes no input. */
  input?: S;
  /** Inputs you can type without a flag, in order: `["key"]` lets you run `voz jira issue PROJ-1`. */
  positional?: readonly (keyof S["properties"] & string)[];
  /** Set when the tool only reads, so agents can call it without asking you. */
  readOnly?: boolean;
  /** Return within 60 seconds. After that the caller gets an error. */
  run(input: Generated<S>, ctx: Context): Awaitable<unknown>;
};

/** A row in a list the user sees on the extension's page in Settings */
export type ListItem = { id: string; title: string; detail?: string };

/**
 * A list on the extension's page in Settings, such as what it learned. Voz calls `items` when the page opens.
 * With `remove`, each row gets a delete button.
 */
export type List = {
  id: string;
  title: string;
  /** One line under the title, saying what the rows are */
  description?: string;
  items(): Awaitable<ListItem[]>;
  remove?(id: string): Awaitable<void>;
};

export type ActionHandle = {
  update(changes: { hidden?: boolean }): void;
};

export type Activity = {
  title: string;
  since?: number;
  stop?(ctx: Context): Awaitable<void>;
  /** Runs when the user clicks the activity in the notch or the Voz panel. */
  open?(ctx: Context): Awaitable<void>;
};

export type RunningActivity = {
  end(): void;
  /** Listens until `stop()` or until the activity ends. */
  transcribeLive(options?: LiveTranscribeOptions): Promise<LiveTranscription>;
};

export type HistoryEntry = { text: string; seconds?: number; file?: string };

type SettingBase = { title: string; description?: string };

export type Setting =
  | (SettingBase & {
      type: "string";
      default: string;
      options?: string[];
      secret?: boolean;
      required?: boolean;
    })
  | (SettingBase & { type: "number"; default: number })
  | (SettingBase & { type: "boolean"; default: boolean });

export type SettingsSchema = Record<string, Setting>;

export type SettingsValues<Schema extends SettingsSchema> = {
  [Key in keyof Schema]: Schema[Key]["default"];
};

type Awaitable<T> = T | Promise<T>;

export type ExtensionAPI = {
  name: string;
  paths: Paths;
  on(
    event: "beforeCleanup",
    handler: (
      event: BeforeCleanupEvent,
      ctx: TransformContext,
    ) => Awaitable<BeforeCleanupResult>,
  ): void;
  on(
    event: "beforeInsert",
    handler: (
      event: BeforeInsertEvent,
      ctx: TransformContext,
    ) => Awaitable<BeforeInsertResult>,
  ): void;
  on(
    event: "afterRecording",
    handler: (event: RecordingEvent, ctx: Context) => Awaitable<void>,
  ): void;
  on(
    event: "afterInsert",
    handler: (event: AfterInsertEvent, ctx: Context) => Awaitable<void>,
  ): void;
  on(
    event: "audioDrop",
    handler: (event: AudioDropEvent, ctx: Context) => Awaitable<void>,
  ): void;
  registerCommand(command: Command): void;
  registerSpeechModel(model: SpeechModel): void;
  registerCleanupModel(model: CleanupModel): void;
  registerCleanupStep(step: CleanupStep): void;
  registerAction(action: Action): ActionHandle;
  registerTool<const S extends ObjectSchema>(tool: Tool<S>): void;
  registerList(list: List): void;
  /**
   * Asks a model outside a handler, for background work. Use `model: "on-device"` to keep it on the Mac and free.
   * Without it, it runs the model the user picked. Times out after 60 seconds.
   */
  generate<const S extends Schema>(request: GenerateRequest<S>): Promise<Generated<S>>;
  startActivity(activity: Activity): RunningActivity;
  addHistory(entry: HistoryEntry): void;
  /** What the user wrote through Voz: dictations, and drafts with what happened to them. Read-only. */
  history(query?: HistoryQuery): Promise<Written[]>;
  /**
   * Reads the window in front now. Null when Voz can't read it, as in password managers and private browser windows.
   * Needs `"screen": true` under `"voz"` in the package.json, and the Extensions page shows that the extension reads the screen.
   * Voz keeps nothing: the extension decides what to store, in `paths.data`.
   */
  screen(): Promise<ScreenText | null>;
  settings<Schema extends SettingsSchema>(
    schema: Schema,
  ): SettingsValues<Schema>;
};

export type Extension = (voz: ExtensionAPI) => Awaitable<void>;

export const apiVersion: 8;

export function defineExtension(extension: Extension): Extension;
