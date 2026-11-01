import Foundation

/// Bumped when a request or reply changes shape, so an old `voz` and a new app refuse each other instead of guessing
enum ControlProtocol {
    static let version = 1
}

/// One thing you can do in Voz, the same from the terminal, an agent or an AI app over MCP.
/// Names are paths: `vocabulary/add`, `voz-jira/issues`. The terminal also takes them as words: `voz vocabulary add`
struct ControlCommand: Sendable {
    let name: String
    let summary: String
    let input: GenerationSpec
    var positionals: [String] = []
    /// Changes nothing, so agents can call it without asking you
    var readOnly = false
    /// The extension that added it, or nil for Voz's own commands
    var source: String?
    /// Runs only in a terminal, such as `dev`, which streams logs until Ctrl-C. AI apps don't see it over MCP
    var terminalOnly = false
    let run: @MainActor @Sendable ([String: JSONValue]) async throws -> ControlOutput

    /// How a person types it: `vocabulary add`
    var words: String { name.replacingOccurrences(of: "/", with: " ") }

    var usage: String {
        let flags = (input.properties ?? []).map { property in
            if positionals.contains(property.name) { return property.optional ? "[\(property.name)]" : "<\(property.name)>" }
            let flag = property.schema.type == "boolean" ? "--\(property.name)" : "--\(property.name) <\(property.schema.choices?.joined(separator: "|") ?? property.schema.type)>"
            return property.optional ? "[\(flag)]" : flag
        }
        return (["voz", words] + flags).joined(separator: " ")
    }

    var help: String {
        let properties = input.properties ?? []
        let width = properties.map { $0.name.count + 2 }.max() ?? 0
        let lines = properties.map { property in
            let label = positionals.contains(property.name) ? property.name : "--\(property.name)"
            return "  \(label.padding(toLength: width, withPad: " ", startingAt: 0))  \(property.schema.description ?? "")"
        }
        let input = properties.isEmpty || properties.contains { $0.name == "input" }
            ? [] : ["", "  --input <json>  All input as one JSON object. Pass - to read it from stdin"]
        return ([summary, "", "usage: \(usage)"] + (lines.isEmpty ? [] : [""] + lines) + input).joined(separator: "\n")
    }
}

/// What a command returns: the value for `--json` and agents, and the text a person reads
struct ControlOutput: Sendable {
    let value: JSONValue
    let text: String

    init(_ value: JSONValue, text: String) {
        self.value = value
        self.text = text
    }

    init(_ value: some Encodable, text: String) throws {
        self.init(try JSONValue(encoding: value), text: text)
    }

    /// `changed: false` says it was already so, like "voz-jira is already on". That still succeeds, so scripts can repeat commands
    static func message(_ text: String, changed: Bool = true) -> ControlOutput {
        ControlOutput(.object(["message": .string(text), "changed": .bool(changed)]), text: text)
    }
}

struct ControlError: Error, Equatable, Codable {
    enum Code: String, Codable {
        case usage, notFound, invalid, failed, unreachable, versionMismatch, noSpeech
    }

    let code: Code
    let error: String

    static func usage(_ message: String) -> ControlError { ControlError(code: .usage, error: message) }
    static func notFound(_ message: String) -> ControlError { ControlError(code: .notFound, error: message) }
    static func invalid(_ message: String) -> ControlError { ControlError(code: .invalid, error: message) }
    static func failed(_ message: String) -> ControlError { ControlError(code: .failed, error: message) }

    var exitCode: Int32 {
        switch code {
        case .usage: 2
        case .unreachable: 3
        case .noSpeech: 4
        case .notFound, .invalid, .failed, .versionMismatch: 1
        }
    }
}

extension GenerationSpec {
    static func object(_ properties: [Property], description: String? = nil) -> GenerationSpec {
        GenerationSpec(type: "object", description: description, properties: properties)
    }

    static func string(_ description: String?, choices: [String]? = nil) -> GenerationSpec {
        GenerationSpec(type: "string", description: description, choices: choices)
    }

    static func integer(_ description: String?) -> GenerationSpec { GenerationSpec(type: "integer", description: description) }
    static func number(_ description: String?) -> GenerationSpec { GenerationSpec(type: "number", description: description) }
    static func boolean(_ description: String?) -> GenerationSpec { GenerationSpec(type: "boolean", description: description) }

    var jsonSchema: JSONValue {
        var schema: [String: JSONValue] = ["type": .string(type)]
        if let description { schema["description"] = .string(description) }
        if let choices { schema["enum"] = .array(choices.map(JSONValue.string)) }
        if let items { schema["items"] = items.jsonSchema }
        if let properties {
            schema["properties"] = .object(Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0.schema.jsonSchema) }))
            schema["required"] = .array(properties.filter { !$0.optional }.map { .string($0.name) })
            schema["additionalProperties"] = .bool(false)
        }
        return .object(schema)
    }
}

/// Turns terminal words or agent JSON into arguments that match a command's input
enum ControlArguments {
    static let trueWords: Set = ["true", "yes", "on", "1"]
    static let falseWords: Set = ["false", "no", "off", "0"]

    static func parse(_ words: [String], for command: ControlCommand) throws -> [String: JSONValue] {
        let properties = command.input.properties ?? []
        let takesInput = !properties.contains { $0.name == "input" }
        var base: [String: JSONValue] = [:]
        var arguments: [String: JSONValue] = [:]
        var positionals = command.positionals[...]
        var index = words.startIndex
        while index < words.endIndex {
            let word = words[index]
            index += 1
            guard word.hasPrefix("--") else {
                guard let name = positionals.popFirst() else { throw ControlError.usage("Unexpected argument \"\(word)\"") }
                arguments[name] = .string(word)
                continue
            }
            let flag = word.dropFirst(2)
            let name = String(flag.prefix { $0 != "=" })
            if takesInput, name == "input" {
                let raw = flag.contains("=") ? String(flag.drop { $0 != "=" }.dropFirst()) : index < words.endIndex ? words[index] : ""
                if !flag.contains("=") { index += 1 }
                base = try object(from: raw)
                continue
            }
            if name.hasPrefix("no-"), let property = properties.first(where: { $0.name == name.dropFirst(3) && $0.schema.type == "boolean" }) {
                arguments[property.name] = .bool(false)
                continue
            }
            guard let property = properties.first(where: { $0.name == name }) else {
                throw ControlError.usage("Unknown flag --\(name).\(suggestion(for: name, in: properties.map(\.name), prefix: "--"))")
            }
            if let equals = flag.firstIndex(of: "=") {
                append(.string(String(flag[flag.index(after: equals)...])), to: &arguments, name: name, schema: property.schema)
            } else if property.schema.type == "boolean" {
                let explicit = index < words.endIndex && (trueWords.contains(words[index]) || falseWords.contains(words[index]))
                arguments[name] = .bool(explicit ? trueWords.contains(words[index]) : true)
                if explicit { index += 1 }
            } else {
                guard index < words.endIndex else { throw ControlError.usage("--\(name) needs a value") }
                append(.string(words[index]), to: &arguments, name: name, schema: property.schema)
                index += 1
            }
        }
        return try validate(base.merging(arguments) { $1 }, for: command.input)
    }

    private static func object(from raw: String) throws -> [String: JSONValue] {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)), let object = value.object else {
            throw ControlError.usage("--input must be a JSON object, such as '{\"limit\": 5}'")
        }
        return object
    }

    static func validate(_ arguments: [String: JSONValue], for input: GenerationSpec) throws -> [String: JSONValue] {
        let properties = input.properties ?? []
        if let unknown = arguments.keys.sorted().first(where: { name in !properties.contains { $0.name == name } }) {
            throw ControlError.usage("Unknown argument \"\(unknown)\"")
        }
        if let missing = properties.first(where: { !$0.optional && arguments[$0.name] == nil }) {
            throw ControlError.usage("--\(missing.name) is required")
        }
        return try arguments.reduce(into: [:]) { result, argument in
            result[argument.key] = try coerce(argument.value, to: properties.first { $0.name == argument.key }!.schema, name: argument.key)
        }
    }

    static func suggestion(for word: String, in candidates: [String], prefix: String = "") -> String {
        guard let closest = candidates.min(by: { distance(word, $0) < distance(word, $1) }), distance(word, closest) <= 2 else { return "" }
        return " Did you mean \(prefix)\(closest)?"
    }

    private static func append(_ value: JSONValue, to arguments: inout [String: JSONValue], name: String, schema: GenerationSpec) {
        guard schema.type == "array" else { return arguments[name] = value }
        let added: [JSONValue]
        if case .string(let text) = value, text.hasPrefix("["), case .array(let values)? = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) {
            added = values
        } else {
            added = [value]
        }
        if case .array(let values) = arguments[name] { arguments[name] = .array(values + added) } else { arguments[name] = .array(added) }
    }

    private static func coerce(_ value: JSONValue, to schema: GenerationSpec, name: String) throws -> JSONValue {
        switch (schema.type, value) {
        case ("string", .string(let text)):
            if let choices = schema.choices, !choices.contains(text) { throw ControlError.usage("--\(name) must be one of \(choices.joined(separator: ", ")), not \"\(text)\"") }
            return value
        case ("integer", .number(let number)) where number == number.rounded(): return value
        case ("integer", .string(let text)):
            guard let number = Int(text) else { throw ControlError.usage("--\(name) must be a whole number, not \"\(text)\"") }
            return .number(Double(number))
        case ("number", .number): return value
        case ("number", .string(let text)):
            guard let number = Double(text) else { throw ControlError.usage("--\(name) must be a number, not \"\(text)\"") }
            return .number(number)
        case ("boolean", .bool): return value
        case ("boolean", .string(let text)) where trueWords.contains(text) || falseWords.contains(text): return .bool(trueWords.contains(text))
        case ("object", .string(let text)): return try coerce(json(text, name: name), to: schema, name: name)
        case ("array", .string(let text)) where text.hasPrefix("["): return try coerce(json(text, name: name), to: schema, name: name)
        case ("array", .array(let values)): return .array(try values.map { try coerce($0, to: schema.items ?? .string(nil), name: name) })
        case ("array", _): return .array([try coerce(value, to: schema.items ?? .string(nil), name: name)])
        case ("object", .object): return value
        default: throw ControlError.usage("--\(name) must be a \(schema.type), not \(value.text)")
        }
    }

    private static func json(_ text: String, name: String) throws -> JSONValue {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { throw ControlError.usage("--\(name) must be JSON, not \(text)") }
        return value
    }

    private static func distance(_ left: String, _ right: String) -> Int {
        let left = Array(left), right = Array(right)
        var row = Array(0...right.count)
        for (i, l) in left.enumerated() {
            var previous = row[0]
            row[0] = i + 1
            for (j, r) in right.enumerated() {
                let current = row[j + 1]
                row[j + 1] = l == r ? previous : min(previous, row[j], row[j + 1]) + 1
                previous = current
            }
        }
        return row[right.count]
    }
}

extension GenerationSpec: Equatable {
    static func == (left: GenerationSpec, right: GenerationSpec) -> Bool {
        left.jsonSchema == right.jsonSchema
    }
}
