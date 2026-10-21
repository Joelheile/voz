import Foundation

public enum VersionPing: String, Sendable, Encodable {
    case install
    case update

    public func body(version: String, projectToken: String) throws -> Data {
        let payload = Payload(
            uuid: UUID().uuidString,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            apiKey: projectToken,
            distinctID: UUID().uuidString,
            properties: .init(kind: self, version: version)
        )
        return try JSONEncoder().encode(payload)
    }
}

private struct Payload: Encodable {
    struct Properties: Encodable {
        let kind: VersionPing
        let version: String
        let processPersonProfile = false
        let geoIPDisable = true

        enum CodingKeys: String, CodingKey {
            case kind, version
            case processPersonProfile = "$process_person_profile"
            case geoIPDisable = "$geoip_disable"
        }
    }

    let uuid: String
    let timestamp: String
    let apiKey: String
    let event = "version_ping"
    let distinctID: String
    let properties: Properties

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case event, uuid, timestamp
        case distinctID = "distinct_id"
        case properties
    }
}
