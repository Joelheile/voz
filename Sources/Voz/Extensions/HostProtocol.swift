import AppKit

struct HostApp: Codable, Equatable, Sendable {
    let bundleID: String?
    let name: String?
    let website: String?

    init(bundleID: String?, name: String?, website: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.website = website
    }

    /// Reads the website off the main thread, because Accessibility can take tens of milliseconds
    @MainActor
    static func front() -> Task<HostApp, Never> {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier, name = app?.localizedName
        guard let pid = app?.processIdentifier, let bundleID, FocusedWebsite.browsers.contains(bundleID), AXIsProcessTrusted() else {
            return Task { HostApp(bundleID: bundleID, name: name) }
        }
        return Task.detached { HostApp(bundleID: bundleID, name: name, website: FocusedWebsite.hostname(pid: pid)) }
    }
}

struct HostManifest: Decodable, Equatable, Sendable {
    let extensions: [String]
    let events: [String]
    let commands: [ExtensionCommand]
    let speechModels: [HostComponent]
    let cleanupModels: [HostComponent]
    let cleanupSteps: [HostComponent]
    let actions: [ExtensionAction]
    let tools: [ExtensionTool]
    /// Missing from hosts older than API 8
    let lists: [SettingsList]?
    let settings: [ExtensionSettings]
    let errors: [LoadError]
    /// Extensions whose package.json asks to read the screen
    let screen: [String]?

    func subscribes(to hook: HostHook) -> Bool {
        events.contains(hook.rawValue)
    }
}

struct HostComponent: Decodable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
}

enum CommandPosition: String, Codable, Sendable {
    case start, end, anywhere

    /// A command at the start wins over one at the end, which wins over one anywhere
    var rank: Int {
        switch self {
        case .start: 2
        case .end: 1
        case .anywhere: 0
        }
    }
}

struct ExtensionCommand: Decodable, Equatable, Hashable, Sendable {
    let `extension`: String
    let phrase: String
    let at: CommandPosition
}

struct ExtensionAction: Decodable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let hotkey: String?
    let hidden: Bool
    let `extension`: String
    var when: ActionCondition? = nil

    var hotkeyLabel: String? {
        hotkey.flatMap { Hotkey.tap(named: $0)?.displayName ?? (try? KeyChord(parsing: $0).label) }
    }

    /// Of the actions that share a hotkey, the one whose `when` holds. Actions without `when` run otherwise,
    /// and with none of those, the hotkey still runs the first action instead of doing nothing.
    static func pick(_ candidates: [ExtensionAction], hasSelection: Bool) -> ExtensionAction? {
        candidates.first { $0.when == .selection && hasSelection } ?? candidates.first { $0.when == nil } ?? candidates.first
    }
}

enum ActionCondition: String, Decodable, Sendable {
    case selection
}

struct ExtensionTool: Decodable, Equatable, Sendable {
    let id: String
    let description: String
    let input: GenerationSpec
    let readOnly: Bool
    /// Inputs you can type without a flag, in order: `voz jira issue PROJ-1`
    let positional: [String]?
    let `extension`: String
}

/// A list on an extension's page in Settings, such as what Reply learned about your writing
struct SettingsList: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let description: String
    let removable: Bool
    let `extension`: String
}

struct SettingsListItem: Codable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String?
}

struct ExtensionSettings: Decodable, Equatable, Sendable {
    let `extension`: String
    let fields: [SettingField]
}

struct SettingField: Decodable, Equatable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case string, number, boolean
    }

    let key: String
    let type: Kind
    let title: String
    let description: String?
    let `default`: SettingValue
    let options: [String]?
    let secret: Bool?
    let required: Bool?

    func needsValue(in config: [String: SettingValue]) -> Bool {
        required == true && value(in: config) == .string("")
    }

    func value(in config: [String: SettingValue]) -> SettingValue {
        guard let value = config[key], value.kind == type else { return self.default }
        if case .string(let string) = value, let options, !options.contains(string) { return self.default }
        return value
    }
}

enum SettingValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    var kind: SettingField.Kind {
        switch self {
        case .string: .string
        case .number: .number
        case .boolean: .boolean
        }
    }

    var text: String {
        switch self {
        case .string(let value): value
        case .number(let value): value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .boolean(let value): String(value)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        }
    }
}

enum HostHook: String, Sendable {
    case beforeInsert
    case beforeCleanup
    case afterRecording
    case afterInsert
    case audioDrop
}

struct LoadError: Decodable, Equatable, Sendable {
    let `extension`: String
    let message: String
}

enum HostEvent: Encodable, Sendable {
    case afterRecording(path: String, seconds: Double)
    case afterInsert(text: String, raw: String)
    case audioDrop(path: String)

    var hook: HostHook {
        switch self {
        case .afterRecording: .afterRecording
        case .afterInsert: .afterInsert
        case .audioDrop: .audioDrop
        }
    }

    private enum Keys: String, CodingKey { case path, seconds, text, raw }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .afterRecording(let path, let seconds):
            try container.encode(path, forKey: .path)
            try container.encode(seconds, forKey: .seconds)
        case .afterInsert(let text, let raw):
            try container.encode(text, forKey: .text)
            try container.encode(raw, forKey: .raw)
        case .audioDrop(let path):
            try container.encode(path, forKey: .path)
        }
    }
}

enum HostAction: Equatable, Sendable {
    case insert(Insertion)
    case press(String)
    case notify(String)
    case startActivity(ExtensionActivity)
    case endActivity(String)
    case openNote(ExtensionNote)
    case closeNote(String)
    case addHistory(ExtensionHistoryEntry)
    case actions([ExtensionAction])
    case busy(String)
    case idle(String, succeeded: Bool)
}

struct BusyParams: Decodable {
    let id: String
}

struct IdleParams: Decodable {
    let id: String
    let ok: Bool
    let remaining: Double
}

struct BusyCancel: Encodable {
    let id: String
}

struct ActionsParams: Decodable {
    let actions: [ExtensionAction]
}

struct ExtensionActivity: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let since: Date
    let stoppable: Bool
    let openable: Bool

    private enum CodingKeys: String, CodingKey { case id, title, since, stoppable, openable }

    init(id: String, title: String, since: Date, stoppable: Bool, openable: Bool) {
        self.id = id
        self.title = title
        self.since = since
        self.stoppable = stoppable
        self.openable = openable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        since = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .since) / 1000)
        stoppable = try container.decode(Bool.self, forKey: .stoppable)
        openable = try container.decode(Bool.self, forKey: .openable)
    }
}

struct ExtensionNote: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let text: String
}

struct AskParams: Decodable, Equatable, Sendable {
    let call: Int
    let deadline: Double
    let title: String
    let fields: [AskField]
    let buttons: [String]
    /// Milliseconds the handler had left when it asked. Its clock restarts with this much once the user answers.
    let remaining: Double
}

struct AskField: Decodable, Equatable, Sendable {
    enum Kind: String, Decodable, Sendable { case text, date, choice }

    let id: String
    let label: String
    let type: Kind
    let value: JSONValue
    let options: [String]?
}

struct AskAnswer: Encodable, Equatable, Sendable {
    let button: String
    let values: [String: JSONValue]
}

struct FieldParams: Decodable, Equatable, Sendable {
    let call: Int
    let deadline: Double
}

/// Text an extension inserts. `source` names the extension, so Voz can save it as a draft.
struct Insertion: Decodable, Equatable, Sendable {
    let text: String
    var source: String? = nil
    var instruction: String? = nil
}

struct HistoryParams: Decodable, Equatable, Sendable {
    let call: Int
    let deadline: Double
    let thread: String?
    let source: String?
    let limit: Int?
}

struct SelectParams: Decodable, Equatable, Sendable {
    let call: Int
    let deadline: Double
    let start: Int
    let length: Int

    var range: TextRange { TextRange(start: start, length: length) }
}

struct ExtensionHistoryEntry: Decodable, Equatable, Sendable {
    let `extension`: String
    let text: String
    let seconds: Double
    let file: String?
}

struct HostLaunchArguments: Encodable {
    let home: String
    let settings: String
    let extensionsDirectory: String
    let packages: [String]
}

struct HostRequest<Params: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Params
    let deadline: Double
}

struct HostReply<Params: Encodable>: Encodable {
    let method: String
    let params: Params
    let deadline: Double
}

struct CallReply: Encodable {
    let call: Int
    let json: String?
    let error: String?
}

struct TranscribeFileParams: Decodable, Sendable {
    let call: Int
    let path: String
    let speakers: Bool
    let deadline: Double
}

struct LiveStartParams: Decodable, Sendable {
    let call: Int
    let session: String
    let activity: String
    let speakers: Bool
    let systemAudio: Bool
    let deadline: Double
}

struct LiveStopParams: Decodable, Sendable {
    let call: Int
    let session: String
    let deadline: Double
}

struct LiveTranscriptParams: Encodable {
    let session: String
    let transcript: FileTranscript
}

struct NoteChangeParams: Encodable {
    let note: String
    let text: String
}

struct InsertParams: Encodable {
    let text: String
    let raw: String
    let app: HostApp
}

struct CleanupParams: Encodable {
    let prompt: String
    let mode: CleanupMode
    let app: HostApp
}

struct TranscribeParams: Encodable {
    let model: String
    let path: String
    let seconds: Double
    let app: HostApp
}

struct CleanParams: Encodable {
    let model: String
    let text: String
    let prompt: String
    let app: HostApp
}

struct StepParams: Encodable {
    let step: String
    let text: String
    let app: HostApp
}

struct ActionParams: Encodable {
    let action: String
    let app: HostApp
}

struct ToolParams: Encodable {
    let tool: String
    let input: [String: JSONValue]
    let app: HostApp
}

struct ListParams: Encodable {
    let list: String
    let remove: String?
}

struct ListResult: Decodable {
    let items: [SettingsListItem]
}

struct ToolResult: Decodable {
    let result: JSONValue?
    let error: String?
}

struct CommandParams: Encodable {
    let phrase: String
    let at: CommandPosition
    let text: String
    let app: HostApp
}

struct HostEnvelope: Decodable {
    let id: Int?
    let method: String?
    let requestID: Int?
}

struct HostNotification<Params: Decodable>: Decodable {
    let params: Params
}

struct HostResponse<Result: Decodable>: Decodable {
    let result: Result?
    let error: String?
}

struct TextParams: Decodable {
    let text: String
}

struct IDParams: Decodable {
    let id: String
}

struct ActivityParams: Encodable {
    let activity: String
    let app: HostApp
}

struct PressParams: Decodable {
    let key: String
}

struct TextResult: Decodable {
    let text: String
}

struct EmptyParams: Codable {}

struct EmitParams: Encodable {
    let event: String
    let payload: HostEvent
    let app: HostApp
}

struct EmitResult: Decodable {
    let failed: Bool
}

struct CommandResult: Decodable {
    let handled: Bool
}

struct VoiceCommandMatch: Equatable, Sendable {
    let phrase: String
    let at: CommandPosition
    let text: String
}

enum VoiceCommands {
    private static let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:"))

    static func match(_ text: String, commands: [ExtensionCommand]) -> VoiceCommandMatch? {
        let words = wordRanges(in: text)
        let candidates = commands
            .map { (command: $0, words: WordTokens.alphanumeric($0.phrase)) }
            .filter { !$0.words.isEmpty && $0.words.count <= words.count }
            .sorted { ($0.command.at.rank, $0.words.count) > ($1.command.at.rank, $1.words.count) }
        for candidate in candidates {
            if candidate.command.at == .anywhere {
                guard contains(candidate.words, in: words, of: text) else { continue }
                return VoiceCommandMatch(phrase: candidate.command.phrase, at: .anywhere, text: text.trimmingCharacters(in: separators))
            }
            let spoken = candidate.command.at == .start ? words.prefix(candidate.words.count) : words.suffix(candidate.words.count)
            guard spoken.map({ text[$0].lowercased() }) == candidate.words, let first = spoken.first, let last = spoken.last else { continue }
            let rest = candidate.command.at == .start ? text[last.upperBound...] : text[..<first.lowerBound]
            return VoiceCommandMatch(phrase: candidate.command.phrase, at: candidate.command.at, text: rest.trimmingCharacters(in: separators))
        }
        return nil
    }

    private static func contains(_ phrase: [String], in words: [Range<String.Index>], of text: String) -> Bool {
        let spoken = words.map { text[$0].lowercased() }
        return (0...(spoken.count - phrase.count)).contains { Array(spoken[$0..<($0 + phrase.count)]) == phrase }
    }

    private static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            let isWordCharacter = text[index].isLetter || text[index].isNumber
            if isWordCharacter, start == nil { start = index }
            if !isWordCharacter, let wordStart = start {
                ranges.append(wordStart..<index)
                start = nil
            }
        }
        if let start { ranges.append(start..<text.endIndex) }
        return ranges
    }
}
