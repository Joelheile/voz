import Testing
@testable import Voz

@MainActor
struct ControlTests {
    private let history = ControlCommand(
        name: "history",
        summary: "List dictations, newest first",
        input: .object([
            .init(name: "query", schema: .string("Words in the text or app name"), optional: true),
            .init(name: "limit", schema: .integer("How many to return"), optional: true),
            .init(name: "files", schema: .boolean("Only file transcripts"), optional: true),
        ]),
        positionals: ["query"]
    ) { arguments in
        ControlOutput(.object(arguments), text: arguments.keys.sorted().joined(separator: ","))
    }

    private var center: ControlCenter { ControlCenter(commands: [history]) }

    @Test func flagsAndPositionalsBecomeTypedArguments() throws {
        let arguments = try ControlArguments.parse(["invoice", "--limit", "5", "--files"], for: history)
        #expect(arguments == ["query": .string("invoice"), "limit": .number(5), "files": .bool(true)])
        #expect(try ControlArguments.parse(["--query=a b", "--files", "false"], for: history) == ["query": .string("a b"), "files": .bool(false)])
    }

    @Test func badInputIsAUsageErrorWithTheFix() {
        #expect(throws: ControlError.usage("Unknown flag --limt. Did you mean --limit?")) { try ControlArguments.parse(["--limt", "5"], for: history) }
        #expect(throws: ControlError.usage("--limit must be a whole number, not \"many\"")) { try ControlArguments.parse(["--limit", "many"], for: history) }
        #expect(throws: ControlError.usage("Unexpected argument \"extra\"")) { try ControlArguments.parse(["a", "extra"], for: history) }
        #expect(throws: ControlError.usage("--limit needs a value")) { try ControlArguments.parse(["--limit"], for: history) }
    }

    @Test func agentArgumentsAreCheckedAgainstTheSameSchema() throws {
        #expect(try ControlArguments.validate(["limit": .string("3")], for: history.input) == ["limit": .number(3)])
        #expect(throws: ControlError.usage("Unknown argument \"app\"")) { try ControlArguments.validate(["app": .string("Slack")], for: history.input) }
        let required = GenerationSpec.object([.init(name: "path", schema: .string(nil), optional: false)])
        #expect(throws: ControlError.usage("--path is required")) { try ControlArguments.validate([:], for: required) }
    }

    @Test func runsACommandForTheTerminal() async {
        let reply = await center.handle(["history", "invoice"], json: false)
        #expect(reply == ControlReply(stdout: "query\n", stderr: "", exit: 0))
        let json = await center.handle(["history", "--limit", "2"], json: true)
        #expect(json.stdout == "{\n  \"limit\" : 2\n}\n")
    }

    @Test func helpAndTyposAnswerWithoutRunning() async {
        let help = await center.handle(["history", "--help"], json: false)
        #expect(help.exit == 0)
        #expect(help.stdout.contains("voz history [query] [--limit <integer>] [--files]"))
        #expect(help.stdout.contains("--limit  How many to return"))
        let typo = await center.handle(["histroy"], json: false)
        #expect(typo == ControlReply(stdout: "", stderr: "Unknown command histroy. Did you mean history?\n", exit: 2))
        let jsonError = await center.handle(["histroy"], json: true)
        #expect(jsonError.stderr == "{\"code\":\"usage\",\"error\":\"Unknown command histroy. Did you mean history?\"}\n")
    }

    private func tool(_ name: String) -> ControlCommand {
        ControlCommand(name: name, summary: "Run \(name)", input: .object([.init(name: "key", schema: .string(nil), optional: true)]), positionals: ["key"], source: "voz-jira") { arguments in
            ControlOutput(.string(name + " " + (arguments["key"]?.string ?? "")), text: name + " " + (arguments["key"]?.string ?? ""))
        }
    }

    private var extensionCenter: ControlCenter {
        var vocabulary = tool("vocabulary/add")
        vocabulary.source = nil
        return ControlCenter(commands: [history, tool("voz-jira/issues"), tool("voz-jira/issues/create"), vocabulary])
    }

    @Test func wordsSlashesAndTheOptionalPrefixReachTheSameCommand() async {
        for words in [["jira", "issues", "VOZ-1"], ["voz-jira", "issues", "VOZ-1"], ["voz-jira/issues", "VOZ-1"], ["jira/issues", "VOZ-1"]] {
            #expect(await extensionCenter.handle(words, json: false).stdout == "voz-jira/issues VOZ-1\n")
        }
        #expect(await extensionCenter.handle(["jira", "issues", "create"], json: false).stdout == "voz-jira/issues/create \n")
    }

    @Test func aPartialNameListsWhatFollows() async {
        let group = await extensionCenter.handle(["jira"], json: false)
        #expect(group.exit == 0)
        #expect(group.stdout.contains("voz-jira issues create"))
        #expect(await extensionCenter.handle(["vocabulary"], json: false).stdout.contains("vocabulary add"))
        let unknown = await extensionCenter.handle(["vocabulary", "adds", "--json"], json: false)
        #expect(unknown.exit == 2)
        #expect(unknown.stderr.hasPrefix("Unknown command vocabulary adds."))
        #expect(await extensionCenter.handle(["help", "jira", "issues"], json: false).stdout.contains("usage: voz voz-jira issues [key]"))
    }

    @Test func helpFindsCommandsByWords() async {
        let found = await extensionCenter.handle(["help", "issues"], json: false)
        #expect(found.stdout == "Commands that match \"issues\":\n  voz-jira issues         Run voz-jira/issues\n  voz-jira issues create  Run voz-jira/issues/create\n")
        let none = await extensionCenter.handle(["help", "calendar"], json: false)
        #expect(none.exit == 1)
        #expect(none.stderr.contains("voz search calendar"))
    }

    @Test func localCommandsWorkWithoutTheApp() async {
        let local = ControlCenter(commands: LocalCommands.all(inTerminal: true))
        #expect(LocalCommands.handles(["logs", "--follow"]))
        #expect(!LocalCommands.handles(["history"]))
        #expect(await local.handle(["logs", "--since", "soon"], json: false).exit == 2)
        let served = ControlCenter(commands: LocalCommands.all(inTerminal: false))
        #expect(await served.handle(["logs", "--follow"], json: false).stderr.contains("only in a terminal"))
    }

    @Test func helpSeparatesExtensionCommands() async {
        let help = await extensionCenter.handle(["help"], json: false).stdout
        #expect(help.range(of: "vocabulary add")!.lowerBound < help.range(of: "from extensions")!.lowerBound)
        #expect(help.range(of: "from extensions")!.lowerBound < help.range(of: "voz-jira issues")!.lowerBound)
    }

    @Test func booleansJSONAndInputMerge() throws {
        #expect(try ControlArguments.parse(["--no-files"], for: history) == ["files": .bool(false)])
        #expect(try ControlArguments.parse(["--files", "off"], for: history) == ["files": .bool(false)])
        #expect(try ControlArguments.parse(["--input", "{\"limit\": 3, \"query\": \"a\"}", "--limit", "5"], for: history) == ["limit": .number(5), "query": .string("a")])
        #expect(throws: ControlError.usage("--input must be a JSON object, such as '{\"limit\": 5}'")) { try ControlArguments.parse(["--input", "[1]"], for: history) }
        let tagged = ControlCommand(name: "tag", summary: "", input: .object([.init(name: "tags", schema: GenerationSpec(type: "array", items: .string(nil)), optional: false)])) { _ in .message("") }
        #expect(try ControlArguments.parse(["--tags", "[\"a\", \"b\"]"], for: tagged) == ["tags": .array(["a", "b"])])
        #expect(try ControlArguments.parse(["--tags", "a", "--tags", "b"], for: tagged) == ["tags": .array(["a", "b"])])
    }

    @Test func resultsReadAsTextForPeople() {
        #expect(JSONValue.string("hi").human == "hi")
        #expect(JSONValue.array(["a", "b"]).human == "a\nb")
        #expect(JSONValue.array([.object(["key": "VOZ-1", "title": "Fix it"])]).human == "VOZ-1  Fix it")
        #expect(JSONValue.object(["version": "1.0", "pid": 42]).human == "pid      42\nversion  1.0")
    }

    @Test func schemaForAgentsIsJSONSchema() {
        #expect(history.input.jsonSchema == .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string"), "description": .string("Words in the text or app name")]),
                "limit": .object(["type": .string("integer"), "description": .string("How many to return")]),
                "files": .object(["type": .string("boolean"), "description": .string("Only file transcripts")]),
            ]),
            "required": .array([]),
            "additionalProperties": .bool(false),
        ]))
    }
}
