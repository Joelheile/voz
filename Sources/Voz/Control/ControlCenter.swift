import Foundation

struct ControlReply: Codable, Equatable, Sendable {
    var stdout = ""
    var stderr = ""
    var exit: Int32 = 0
}

/// Runs commands for the terminal and for agents. Extension tools and actions join as `<extension>/<id>`
@MainActor
final class ControlCenter {
    private let list: @MainActor () -> [ControlCommand]

    init(commands: @escaping @MainActor () -> [ControlCommand]) {
        list = commands
    }

    convenience init(commands: [ControlCommand]) {
        self.init { commands }
    }

    var commands: [ControlCommand] { list() }

    func handle(_ words: [String], json: Bool) async -> ControlReply {
        let asksHelp = words.first == "help"
        let words = asksHelp ? Array(words.dropFirst()) : words
        guard let first = words.first, !["--help", "-h"].contains(first) else { return ControlReply(stdout: help + "\n") }
        do {
            let (command, rest) = try resolve(words)
            if asksHelp || rest.contains("--help") || rest.contains("-h") { return ControlReply(stdout: command.help + "\n") }
            let output = try await command.run(try ControlArguments.parse(rest, for: command))
            let text = json ? output.value.pretty : output.text
            return ControlReply(stdout: text.isEmpty ? "" : text + "\n")
        } catch let group as GroupHelp {
            return ControlReply(stdout: group.text + "\n")
        } catch where asksHelp {
            return search(words)
        } catch {
            let failure = Self.failure(error)
            let text = json ? failure.json : failure.error
            return ControlReply(stderr: text + "\n", exit: failure.exitCode)
        }
    }

    func call(_ name: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        let command = try find(name)
        guard !command.terminalOnly else { throw ControlError.usage("Run voz \(command.words) in a terminal.") }
        return try await command.run(try ControlArguments.validate(arguments, for: command.input)).value
    }

    nonisolated static func failure(_ error: any Error) -> ControlError {
        error as? ControlError ?? .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
    }

    private func find(_ name: String) throws -> ControlCommand {
        let commands = commands
        guard let command = commands.first(where: { $0.name == name }) else {
            let suggestion = ControlArguments.suggestion(for: name, in: commands.map(\.name))
            throw ControlError.usage("Unknown command \(name).\(suggestion.isEmpty ? " Run voz help to see them all." : suggestion)")
        }
        return command
    }

    /// Finds the command the leading words name, so `voz jira issues`, `voz voz-jira issues` and `voz voz-jira/issues` all reach `voz-jira/issues`.
    /// The longest name wins. Words that only start a name, like `voz vocabulary`, list what follows
    private func resolve(_ words: [String]) throws -> (ControlCommand, [String]) {
        let commands = commands
        let matches = commands.flatMap { command in
            Self.spellings(of: command).compactMap { tokens in Self.consumed(words, by: tokens).map { (command, tokens.count, $0) } }
        }
        if let (command, _, count) = matches.max(by: { $0.1 < $1.1 }) { return (command, Array(words.dropFirst(count))) }
        let typed = Array(words.prefix { !$0.hasPrefix("-") })
        for length in stride(from: typed.count, to: 0, by: -1) {
            let group = group(Array(typed.prefix(length)))
            guard !group.isEmpty else { continue }
            let listing = (["\(typed.prefix(length).joined(separator: " ")) commands:"] + Self.lines(group)).joined(separator: "\n")
            if length == typed.count { throw GroupHelp(text: listing) }
            throw ControlError.usage("Unknown command \(typed.joined(separator: " ")).\n\n\(listing)")
        }
        let name = typed.first ?? words[0]
        let suggestion = ControlArguments.suggestion(for: name, in: Array(Set(commands.flatMap { Self.spellings(of: $0).map { $0[0] } })))
        throw ControlError.usage("Unknown command \(name).\(suggestion.isEmpty ? " Run voz help to see them all." : suggestion)")
    }

    /// `voz help <words>` when no command has that name: commands whose name or summary has every word
    private func search(_ words: [String]) -> ControlReply {
        let terms = words.map { $0.lowercased() }
        let found = commands.filter { command in
            let haystack = "\(command.name) \(command.summary)".lowercased()
            return terms.allSatisfy(haystack.contains)
        }
        let query = words.joined(separator: " ")
        guard !found.isEmpty else {
            return ControlReply(stderr: "No command matches \"\(query)\". Run voz help to see them all, or voz search \(query) to find an extension that adds one.\n", exit: 1)
        }
        return ControlReply(stdout: (["Commands that match \"\(query)\":"] + Self.lines(found)).joined(separator: "\n") + "\n")
    }

    /// Words that only start command names, like `voz vocabulary`, list the commands they start
    private struct GroupHelp: Error {
        let text: String
    }

    private func group(_ typed: [String]) -> [ControlCommand] {
        commands.filter { command in
            Self.spellings(of: command).contains { tokens in (1..<tokens.count).contains { Self.consumed(typed, by: Array(tokens.prefix($0))) == typed.count } }
        }
    }

    /// `voz-jira/issues` can be typed with or without the `voz-` most extension names start with
    private static func spellings(of command: ControlCommand) -> [[String]] {
        let tokens = command.name.split(separator: "/").map(String.init)
        guard command.source != nil, let first = tokens.first, first.hasPrefix("voz-") else { return [tokens] }
        return [tokens, [String(first.dropFirst(4))] + tokens.dropFirst()]
    }

    /// How many words spell out `tokens`. A word may hold several tokens joined by `/`
    private static func consumed(_ words: [String], by tokens: [String]) -> Int? {
        var token = 0, word = 0
        while token < tokens.count {
            guard word < words.count else { return nil }
            let parts = words[word].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard token + parts.count <= tokens.count, Array(tokens[token..<token + parts.count]) == parts else { return nil }
            token += parts.count
            word += 1
        }
        return word
    }

    private static func lines(_ commands: [ControlCommand]) -> [String] {
        let width = commands.map(\.words.count).max() ?? 0
        return commands.map { "  \($0.words.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.summary)" }
    }

    private var help: String {
        let commands = commands
        let added = commands.filter { $0.source != nil }
        return ([
"Control Voz from the terminal or an agent. Add --json for JSON, --help after a command for its flags.",
            "Find a command with voz help <words>. Build an extension with voz guide.",
            "", "commands:",
        ] + Self.lines(commands.filter { $0.source == nil })
            + (added.isEmpty ? [] : ["", "from extensions (the voz- prefix is optional):"] + Self.lines(added))).joined(separator: "\n")
    }
}

extension ControlError {
    var json: String { (try? String(decoding: JSONEncoder.control.encode(self), as: UTF8.self)) ?? error }
}
