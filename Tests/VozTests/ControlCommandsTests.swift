import Testing
@testable import Voz

@MainActor
struct ControlCommandsTests {
    @Test func historyFiltersByWordsNewestFirst() async throws {
        let (commands, _) = try makeControlCommands([makeRecord("send the invoice", at: 1), makeRecord("lunch at noon", at: 2), makeRecord("invoice paid", at: 3)])
        let center = ControlCenter(commands: commands.all)
        let reply = await center.handle(["history", "invoice", "--limit", "5"], json: false)
        #expect(reply.exit == 0)
        #expect(reply.stdout.contains("invoice paid"))
        #expect(!reply.stdout.contains("lunch"))
        #expect(reply.stdout.range(of: "invoice paid")!.lowerBound < reply.stdout.range(of: "send the invoice")!.lowerBound)
    }

    @Test func lastPrintsOnlyTheText() async throws {
        let (commands, _) = try makeControlCommands([makeRecord("first", at: 1), makeRecord("second", at: 2)])
        let reply = await ControlCenter(commands: commands.all).handle(["last"], json: false)
        #expect(reply.stdout == "second\n")
    }

    @Test func badDateIsAUsageError() async throws {
        let (commands, _) = try makeControlCommands()
        let reply = await ControlCenter(commands: commands.all).handle(["history", "--since", "yesterday"], json: false)
        #expect(reply.exit == 2)
        #expect(reply.stderr.contains("--since must be a date like"))
    }

    @Test func feedbackNeedsAMessageAndAnOfficialBuild() async throws {
        let (commands, _) = try makeControlCommands()
        let center = ControlCenter(commands: commands.all)
        let empty = await center.handle(["feedback", " "], json: false)
        #expect(empty.exit == 2)
        #expect(empty.stderr.contains("voz feedback"))
        let fork = await center.handle(["feedback", "Short words get cut off"], json: false)
        #expect(fork.exit == 1)
        #expect(fork.stderr.contains("github.com/Joelheile/voz"))
    }

    @Test func settingsChangeAndSuggestKeys() async throws {
        let (commands, settings) = try makeControlCommands()
        let center = ControlCenter(commands: commands.all)
        #expect(await center.handle(["settings", "soundCues", "false"], json: false).exit == 0)
        #expect(settings.soundCues == false)
        #expect(await center.handle(["settings", "cleanupMode", "heavy"], json: false).exit == 0)
        #expect(settings.cleanupMode == .heavy)
        let typo = await center.handle(["settings", "soundCue"], json: false)
        #expect(typo.stderr.contains("Did you mean soundCues?"))
        #expect(await center.handle(["settings", "soundCues", "maybe"], json: false).exit == 2)
    }

    @Test func repeatingASettingSucceedsWithoutChange() async throws {
        let (commands, settings) = try makeControlCommands()
        let center = ControlCenter(commands: commands.all)
        settings.soundCues = true
        #expect(await center.handle(["settings", "soundCues", "off"], json: false).stdout == "Set soundCues to false.\n")
        #expect(settings.soundCues == false)
        let again = await center.handle(["settings", "soundCues", "no"], json: true)
        #expect(again.exit == 0)
        #expect(again.stdout.contains("\"changed\" : false"))
        #expect(await center.handle(["settings", "logText", "on"], json: false).exit == 0)
        #expect(settings.logIncludesText)
    }

    @Test func dictationStartsAndStopsOnce() async throws {
        let dictation = FakeDictation()
        let (commands, _) = try makeControlCommands(dictation: dictation)
        let center = ControlCenter(commands: commands.all)
        #expect(await center.handle(["dictation", "stop"], json: false).stdout == "Not recording.\n")
        #expect(await center.handle(["dictation", "start"], json: false).exit == 0)
        #expect(dictation.phase == .recording)
        #expect(await center.handle(["dictation", "start"], json: false).stdout == "Already recording.\n")
        #expect(await center.handle(["dictation", "toggle"], json: false).exit == 0)
        #expect(dictation.phase == .transcribing)
        #expect(await center.handle(["dictation", "start"], json: false).exit == 1)
        dictation.phase = .idle
        dictation.canRecord = false
        #expect(await center.handle(["dictation", "start"], json: false).stderr.contains("voz status"))
    }

    @Test func stopPrintsTheTextInsteadOfInsertingIt() async throws {
        let dictation = FakeDictation()
        let (commands, _) = try makeControlCommands([makeRecord("older dictation")], dictation: dictation)
        let center = ControlCenter(commands: commands.all)
        #expect(await center.handle(["dictation", "stop", "--print"], json: false).exit == 1)
        dictation.phase = .recording
        dictation.heard = "ship it on friday"
        #expect(await center.handle(["dictation", "stop", "--print"], json: false).stdout == "ship it on friday\n")
        dictation.phase = .recording
        dictation.heard = nil
        let silent = await center.handle(["dictation", "stop", "--print"], json: false)
        #expect(silent.exit == 4)
        #expect(silent.stderr.contains("no speech"))
    }

    @Test func terminalOnlyCommandsStayOffMCP() async throws {
        let (commands, _) = try makeControlCommands()
        let center = ControlCenter(commands: commands.all)
        guard case .array(let listed) = try await center.call("commands", arguments: [:]) else { Issue.record("commands returned no list"); return }
        let names = listed.compactMap { $0.object?["name"]?.string }
        #expect(names.contains("list"))
        #expect(!names.contains("install") && !names.contains("dev") && !names.contains("mcp") && !names.contains("start"))
        await #expect(throws: ControlError.self) { try await center.call("install", arguments: ["package": "voz-jira"]) }
        #expect(await center.handle(["help"], json: false).stdout.contains("  install "))
    }

    @Test func vocabularyAddsListsAndRemovesWords() async throws {
        let (commands, _) = try makeControlCommands()
        let center = ControlCenter(commands: commands.all)
        #expect(await center.handle(["vocabulary", "add", "Kubernetes"], json: false).stdout == "Added Kubernetes.\n")
        #expect(await center.handle(["vocabulary", "add", "kubernetes"], json: false).stdout.contains("already"))
        #expect(await center.handle(["vocabulary", "add", "cube -> Kube"], json: false).stdout == "Voz now writes Kube when it hears cube.\n")
        #expect(await center.handle(["vocabulary", "list"], json: false).stdout == "Kube  cube\nKubernetes\n")
        #expect(await center.handle(["vocabulary", "remove", "Kubernetes"], json: false).stdout == "Removed Kubernetes.\n")
        #expect(await center.handle(["vocabulary", "remove", "Kubernetes"], json: false).stdout.contains("not in your vocabulary"))
    }

    @Test func statusReportsWhatDictationNeeds() async throws {
        let (commands, _) = try makeControlCommands()
        let value = try await ControlCenter(commands: commands.all).call("status", arguments: [:])
        #expect(value.object?["dictation"] == "idle")
        #expect(value.object?["microphone"] != nil)
        #expect(value.object?["extensions"] == .array([]))
    }

    @Test func enableNamesOnlyInstalledExtensions() async throws {
        let (commands, _) = try makeControlCommands()
        let reply = await ControlCenter(commands: commands.all).handle(["enable", "voz-jira"], json: true)
        #expect(reply.exit == 1)
        #expect(reply.stderr.contains("\"code\":\"notFound\""))
    }

    @Test func commandsListsSchemasAndReadOnly() async throws {
        let (commands, _) = try makeControlCommands()
        let value = try await ControlCenter(commands: commands.all).call("commands", arguments: [:])
        guard case .array(let items) = value else { Issue.record("Expected a list"); return }
        let history = items.first { $0.object?["name"] == .string("history") }
        #expect(history?.object?["readOnly"] == .bool(true))
        #expect(history?.object?["inputSchema"]?.object?["type"] == .string("object"))
        let enable = items.first { $0.object?["name"] == .string("enable") }
        #expect(enable?.object?["readOnly"] == .bool(false))
    }

    @Test func socketRoundTrip() async throws {
        let path = temporarySocketPath()
        let (commands, _) = try makeControlCommands([makeRecord("hello socket")])
        let server = ControlServer(center: ControlCenter(commands: commands.all), path: path)
        try server.start()
        defer { server.stop() }
        #expect(posixPermissions(fileURL(path)) == 0o600)
        let response = try await Task.detached { try ControlClient.send(ControlRequest(words: ["last"]), path: path) }.value
        #expect(response.reply?.stdout == "hello socket\n")
        let call = try await Task.detached { try ControlClient.send(ControlRequest(call: "nope"), path: path) }.value
        #expect(call.error?.code == .usage)
        let old = try await Task.detached { try ControlClient.send(ControlRequest(version: 0, words: ["last"]), path: path) }.value
        #expect(old.reply?.exit == 1)
        #expect(old.reply?.stderr.contains("different versions") == true)
    }

    @Test func closedAppIsUnreachableAndNeverLaunched() async {
        let path = temporarySocketPath()
        await #expect(throws: ControlError(code: .unreachable, error: "Voz is not running. Run voz start, then try again.")) {
            try await Task.detached { try ControlClient.send(ControlRequest(words: ["last"]), path: path) }.value
        }
    }
}

@MainActor
struct ControlMCPTests {
    private func send(_ request: ControlRequest) -> ControlResponse {
        if request.call == "commands" {
            return ControlResponse(result: .array([.object(["name": "voz-jira/create", "summary": "Create an issue", "readOnly": false, "inputSchema": .object(["type": "object"])])]))
        }
        if request.call == "voz-jira/create" { return ControlResponse(result: .object(["key": "VOZ-1"])) }
        return ControlResponse(error: .notFound("No such command"))
    }

    private func call(_ method: String, _ params: JSONValue = .object([:])) -> JSONValue? {
        ControlMCP.respond(to: .object(["jsonrpc": "2.0", "id": .number(1), "method": .string(method), "params": params]), send: send)
    }

    @Test func listsCommandsAsToolsWithSafeNames() {
        let tools = call("tools/list")?.object?["result"]?.object?["tools"]
        guard case .array(let list) = tools else { Issue.record("Expected tools"); return }
        #expect(list.first?.object?["name"] == "voz-jira_create")
        #expect(list.first?.object?["annotations"]?.object?["readOnlyHint"] == false)
    }

    @Test func callsTheCommandBehindATool() {
        let result = call("tools/call", .object(["name": "voz-jira_create", "arguments": .object([:])]))?.object?["result"]
        #expect(result?.object?["isError"] == nil)
        #expect(result?.text.contains("VOZ-1") == true)
        #expect(result?.object?["structuredContent"] == .object(["key": "VOZ-1"]))
    }

    @Test func unknownMethodsAndNotificationsFollowJSONRPC() {
        #expect(call("resources/list")?.object?["error"]?.object?["code"] == .number(-32601))
        #expect(ControlMCP.respond(to: .object(["jsonrpc": "2.0", "method": "notifications/initialized"]), send: send) == nil)
        #expect(call("initialize", .object(["protocolVersion": "2025-03-26"]))?.object?["result"]?.object?["protocolVersion"] == "2025-03-26")
    }
}
