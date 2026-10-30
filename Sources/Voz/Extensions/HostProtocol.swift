import AppKit

struct HostApp: Codable, Equatable, Sendable {
    let bundleID: String?
    let name: String?

    @MainActor
    static var current: HostApp {
        let app = NSWorkspace.shared.frontmostApplication
        return HostApp(bundleID: app?.bundleIdentifier, name: app?.localizedName)
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
    let settings: [ExtensionSettings]
    let errors: [LoadError]

    func subscribes(to hook: HostHook) -> Bool {
        events.contains(hook.rawValue)
    }
}

struct HostComponent: Decodable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
}

enum CommandPosition: String, Codable, Sendable {
    case start, end
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

    var hotkeyLabel: String? { hotkey.flatMap { try? KeyChord(parsing: $0).label } }
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
    case insert(String)
    case press(String)
    case notify(String)
    case startActivity(ExtensionActivity)
    case endActivity(String)
    case addHistory(ExtensionHistoryEntry)
    case actions([ExtensionAction])
}

struct ActionsParams: Decodable {
    let actions: [ExtensionAction]
}

struct ExtensionActivity: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let since: Date
    let stoppable: Bool

    private enum CodingKeys: String, CodingKey { case id, title, since, stoppable }

    init(id: String, title: String, since: Date, stoppable: Bool) {
        self.id = id
        self.title = title
        self.since = since
        self.stoppable = stoppable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        since = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .since) / 1000)
        stoppable = try container.decode(Bool.self, forKey: .stoppable)
    }
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

struct StopActivityParams: Encodable {
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
            .sorted { ($0.command.at == .start ? 1 : 0, $0.words.count) > ($1.command.at == .start ? 1 : 0, $1.words.count) }
        for candidate in candidates {
            let spoken = candidate.command.at == .start ? words.prefix(candidate.words.count) : words.suffix(candidate.words.count)
            guard spoken.map({ text[$0].lowercased() }) == candidate.words, let first = spoken.first, let last = spoken.last else { continue }
            let rest = candidate.command.at == .start ? text[last.upperBound...] : text[..<first.lowerBound]
            return VoiceCommandMatch(phrase: candidate.command.phrase, at: candidate.command.at, text: rest.trimmingCharacters(in: separators))
        }
        return nil
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
