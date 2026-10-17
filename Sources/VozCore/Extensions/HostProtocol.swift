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
    public let errors: [String]

    public static let beforeInsert = "beforeInsert"
}

public enum HostAction: Equatable, Sendable {
    case insert(String)
    case press(String)
}

struct HostLaunchArguments: Encodable {
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

struct CommandResult: Decodable {
    let handled: Bool
}
