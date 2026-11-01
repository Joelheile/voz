import Foundation

/// Any JSON value, for command arguments and results that cross the socket and MCP
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(encoding value: some Encodable) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder.control.encode(value))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    var text: String {
        switch self {
        case .null: ""
        case .string(let value): value
        case .bool(let value): String(value)
        case .number(let value): SettingValue.number(value).text
        case .array, .object: (try? String(decoding: JSONEncoder.control.encode(self), as: UTF8.self)) ?? ""
        }
    }

    /// What a person reads: text as is, a list one item per line, an object as aligned key and value lines
    var human: String {
        switch self {
        case .array(let values): return values.map(\.line).joined(separator: "\n")
        case .object(let fields):
            let width = fields.keys.map(\.count).max() ?? 0
            return fields.keys.sorted().map { "\($0.padding(toLength: width, withPad: " ", startingAt: 0))  \(fields[$0]!.line)" }.joined(separator: "\n")
        default: return text
        }
    }

    private var line: String {
        switch self {
        case .array(let values): values.map(\.text).joined(separator: ", ")
        case .object(let fields): fields.keys.sorted().map { fields[$0]!.line }.filter { !$0.isEmpty }.joined(separator: "  ")
        default: text
        }
    }

    var pretty: String {
        (try? String(decoding: JSONEncoder.prettyControl.encode(self), as: UTF8.self)) ?? text
    }
}

extension JSONEncoder {
    static var control: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var prettyControl: JSONEncoder {
        let encoder = control
        encoder.outputFormatting.insert(.prettyPrinted)
        return encoder
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
}
