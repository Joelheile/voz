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
    public let commands: [String]
    public let errors: [LoadError]

    public static let beforeInsert = "beforeInsert"
    public static let beforeCleanup = "beforeCleanup"
}

public struct LoadError: Decodable, Equatable, Sendable {
    public let `extension`: String
    public let message: String
}

public enum HostEvent: Encodable, Sendable {
    case recording(path: String, seconds: Double)
    case afterInsert(text: String, raw: String)

    public var name: String {
        switch self {
        case .recording: "recording"
        case .afterInsert: "afterInsert"
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

struct InsertResult: Decodable {
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
