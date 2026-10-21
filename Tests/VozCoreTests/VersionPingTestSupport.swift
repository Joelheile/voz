import Foundation
import VozCore

func makeVersionPingQueue() -> () throws -> VersionPingQueue {
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    return { try VersionPingQueue(defaults: defaults) }
}

func decodeVersionPing(_ data: Data) throws -> PingPayload {
    try JSONDecoder().decode(PingPayload.self, from: data)
}

struct PingPayload: Decodable {
    struct Properties: Decodable {
        let kind: String
        let processPersonProfile: Bool
        let geoIPDisable: Bool
        enum CodingKeys: String, CodingKey {
            case kind
            case processPersonProfile = "$process_person_profile"
            case geoIPDisable = "$geoip_disable"
        }
    }
    let event: String
    let uuid: String
    let timestamp: String
    let distinctID: String
    enum CodingKeys: String, CodingKey {
        case event, uuid, timestamp, properties
        case distinctID = "distinct_id"
    }
    let properties: Properties
}
