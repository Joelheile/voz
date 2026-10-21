import Foundation

public struct HostApp: Codable, Equatable, Sendable {
    public let bundleID: String?
    public let name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct HostManifest: Decodable, Equatable, Sendable {
    public let extensions: [String]
    public let events: [String]
    public let commands: [ExtensionCommand]
    public let speechModels: [HostComponent]
    public let cleanupModels: [HostComponent]
    public let cleanupSteps: [HostComponent]
    public let actions: [ExtensionAction]
    public let settings: [ExtensionSettings]
    public let errors: [LoadError]

    public func subscribes(to hook: HostHook) -> Bool {
        events.contains(hook.rawValue)
    }
}

public struct HostComponent: Decodable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ExtensionCommand: Decodable, Equatable, Hashable, Sendable {
    public let `extension`: String
    public let phrase: String
}

public struct ExtensionAction: Decodable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let hotkey: String?
    public let `extension`: String
}

public struct ExtensionSettings: Decodable, Equatable, Sendable {
    public let `extension`: String
    public let fields: [SettingField]
}

public struct SettingField: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case string, number, boolean
    }

    public let key: String
    public let type: Kind
    public let title: String
    public let description: String?
    public let `default`: SettingValue
    public let options: [String]?
    public let secret: Bool?
    public let required: Bool?

    public func needsValue(in config: [String: SettingValue]) -> Bool {
        required == true && value(in: config) == .string("")
    }

    public func value(in config: [String: SettingValue]) -> SettingValue {
        guard let value = config[key], value.kind == type else { return self.default }
        if case .string(let string) = value, let options, !options.contains(string) { return self.default }
        return value
    }
}

public enum SettingValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    public var kind: SettingField.Kind {
        switch self {
        case .string: .string
        case .number: .number
        case .boolean: .boolean
        }
    }

    public var text: String {
        switch self {
        case .string(let value): value
        case .number(let value): value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .boolean(let value): String(value)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        }
    }
}

public enum HostHook: String, Sendable {
    case beforeInsert
    case beforeCleanup
    case recording
    case afterInsert
}

public struct LoadError: Decodable, Equatable, Sendable {
    public let `extension`: String
    public let message: String
}

public enum HostEvent: Encodable, Sendable {
    case recording(path: String, seconds: Double)
    case afterInsert(text: String, raw: String)

    public var hook: HostHook {
        switch self {
        case .recording: .recording
        case .afterInsert: .afterInsert
        }
    }

    private enum Keys: String, CodingKey { case path, seconds, text, raw }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .recording(let path, let seconds):
            try container.encode(path, forKey: .path)
            try container.encode(seconds, forKey: .seconds)
        case .afterInsert(let text, let raw):
            try container.encode(text, forKey: .text)
            try container.encode(raw, forKey: .raw)
        }
    }
}

public enum HostAction: Equatable, Sendable {
    case insert(String)
    case press(String)
    case notify(String)
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
}

struct InsertParams: Encodable {
    let text: String
    let raw: String
    let app: HostApp
}

struct PromptParams: Codable {
    let prompt: String
}

struct CleanupParams: Encodable {
    let prompt: String
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
    let text: String
    let app: HostApp
}

struct HostEnvelope: Decodable {
    let id: Int?
    let method: String?
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

struct CommandResult: Decodable {
    let handled: Bool
}
