import Testing
import Synchronization
@testable import Voz

@Suite(.enabled(if: installedBun != nil, "Needs Bun at ~/.bun/bin/bun or BUN_PATH"))
struct ExtensionHostTests {
    private let home = temporaryHome()
    private let app = HostApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")

    private func extensionFile(_ name: String, _ source: String) throws {
        try writeFile(source, named: name, in: home.extensions)
    }

    private func makeHost(
        packages: [String] = [],
        actions: RecordedActions = RecordedActions(),
        logs: RecordedLogs = RecordedLogs(),
        generate: @escaping @Sendable (GenerateParams) async throws -> String = { _ in throw ExtensionModelError.unavailable("not in tests") },
        transcribeFile: @escaping @Sendable (TranscribeFileParams) async throws -> FileTranscript = { _ in throw FileTranscriberError.needsParakeet },
        startLive: @escaping @Sendable (LiveStartParams, @escaping @Sendable (FileTranscript) async -> Void) async throws -> Void = { _, _ in throw FileTranscriberError.needsParakeet },
        stopLive: @escaping @Sendable (LiveStopParams) async throws -> FileTranscript = { throw LiveSessionError.unknown($0.session) },
        ask: @escaping @Sendable (AskParams) async -> AskAnswer? = { _ in nil },
        field: @escaping @Sendable () async -> FocusedField? = { nil },
        select: @escaping @Sendable (TextRange) async -> Bool = { _ in false },
        history: @escaping @Sendable (HistoryParams) async throws -> [WrittenText] = { _ in [] },
        screen: @escaping @Sendable () async -> ScreenText? = { nil }
    ) -> ExtensionHost {
        ExtensionHost(
            launch: .init(bun: installedBun!, script: hostScript, home: home, packageDirectories: packages.map(fileURL)),
            onAction: { actions.append($0) },
            onLog: { logs.append($0) },
            onExit: { _ in },
            generate: generate,
            transcribeFile: transcribeFile,
            startLive: startLive,
            stopLive: stopLive,
            ask: ask,
            field: field,
            select: select,
            history: history,
            screen: screen
        )
    }

    @Test func textHandlersChainInLoadOrderWithAppAndConfig() async throws {
        try writeFile(#"{"config":{"b-tag":{"suffix":" #voz"}}}"#, named: "settings.json", in: home.root)
        try extensionFile("a-upper.ts", #"export default (voz) => { voz.on("beforeInsert", (e) => ({ text: e.text.toUpperCase() })); voz.on("beforeCleanup", (e, ctx) => ctx.app.name === "Slack" ? { prompt: e.prompt + " Casual." } : undefined) }"#)
        try extensionFile("b-tag.ts", #"export default (voz) => { const { suffix } = voz.settings({ suffix: { type: "string", title: "Suffix", default: "" } }); voz.on("beforeInsert", (e, ctx) => ({ text: `${e.text} [${ctx.app.name}]${suffix}` })); voz.on("beforeCleanup", (e) => ({ prompt: e.prompt + " Short." })) }"#)
        let host = makeHost()
        let manifest = try await host.start()
        #expect(manifest.extensions == ["a-upper", "b-tag"])
        #expect(Set(manifest.events) == ["beforeInsert", "beforeCleanup"])
        #expect(await host.beforeInsert(text: "hi", raw: "hi", app: app, timeout: .seconds(2)) == "HI [Slack] #voz")
        #expect(await host.beforeCleanup(CleanupPlan(prompt: "Clean.", mode: .heavy), app: app, timeout: .seconds(2)) == CleanupPlan(prompt: "Clean. Casual. Short.", mode: .heavy))
        await host.stop()
    }

    @Test func beforeCleanupPicksTheModePerAppAndIgnoresUnknownModes() async throws {
        try extensionFile("a-notes.ts", #"export default (voz) => voz.on("beforeCleanup", (e, ctx) => ctx.app.name === "Notes" ? { mode: "light" } : { mode: `${e.mode}-ish` })"#)
        let old = home.packages.appendingPathComponent("node_modules/old")
        try writeFile(#"{"name":"old","voz":{"apiVersion":4}}"#, named: "package.json", in: old)
        try writeFile(#"export default (voz) => voz.on("beforeCleanup", (e) => ({ prompt: `${e.prompt} Short.` }))"#, named: "index.ts", in: old)
        let host = makeHost(packages: [old.path])
        let manifest = try await host.start()
        #expect(manifest.errors.isEmpty)
        let notes = HostApp(bundleID: "com.apple.Notes", name: "Notes")
        #expect(await host.beforeCleanup(CleanupPlan(prompt: "Clean.", mode: .heavy), app: notes, timeout: .seconds(2)) == CleanupPlan(prompt: "Clean. Short.", mode: .light))
        #expect(await host.beforeCleanup(CleanupPlan(prompt: "Clean.", mode: .heavy), app: app, timeout: .seconds(2)) == CleanupPlan(prompt: "Clean. Short.", mode: .heavy))
        await host.stop()
    }

    @Test func emptyTextStopsTheChainAndCommandsSendActions() async throws {
        try extensionFile("a-route.ts", #"export default (voz) => voz.on("beforeInsert", (e, ctx) => { ctx.insert("elsewhere"); return { text: "" } })"#)
        try extensionFile("b-never.ts", #"export default (voz) => voz.on("beforeInsert", () => ({ text: "should not run" }))"#)
        try extensionFile("c-send.ts", #"export default (voz) => voz.registerCommand("send it", async (e, ctx) => { ctx.insert(`[${e.text}]`); ctx.press("cmd+return"); ctx.notify("sent") })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        let manifest = try await host.start()
        #expect(manifest.commands.map(\.phrase) == ["send it"])
        #expect(await host.beforeInsert(text: "hello", raw: "hello", app: app, timeout: .seconds(2)) == "")
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "send it", at: .end, text: "hello"), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.insert(Insertion(text: "elsewhere", source: "a-route")), .insert(Insertion(text: "[hello]", source: "c-send")), .press("cmd+return"), .notify("sent")])
        await host.stop()
    }

    @Test func startCommandsGetTheWordsAfterThePhrase() async throws {
        try extensionFile("todo.ts", #"export default (voz) => { voz.registerCommand("todo", (e, ctx) => ctx.notify(`start ${e.text}`), { at: "start" }); voz.registerCommand("todo", (e, ctx) => ctx.notify(`end ${e.text}`)) }"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        let manifest = try await host.start()
        #expect(Set(manifest.commands.map(\.at)) == [.start, .end])
        let start = try #require(VoiceCommands.match("To-do: call Milan tomorrow", commands: manifest.commands + [ExtensionCommand(extension: "x", phrase: "to do", at: .start)]))
        #expect(start == VoiceCommandMatch(phrase: "to do", at: .start, text: "call Milan tomorrow"))
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "todo", at: .start, text: "call Milan"), app: app, timeout: .seconds(2)))
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "todo", at: .end, text: "call Milan"), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("start call Milan"), .notify("end call Milan")])
        await host.stop()
    }

    @Test func anywhereCommandsGetTheWholeDictationAndRankBelowStartAndEnd() async throws {
        try extensionFile("cal.ts", #"export default (voz) => voz.registerCommand({ phrase: "calendar", at: "anywhere", run: (e, ctx) => ctx.notify(e.text) })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        let manifest = try await host.start()
        #expect(manifest.commands.map(\.at) == [.anywhere])
        let text = "Put lunch with Tom in my calendar tomorrow"
        let match = try #require(VoiceCommands.match(text, commands: manifest.commands))
        #expect(match == VoiceCommandMatch(phrase: "calendar", at: .anywhere, text: text))
        #expect(VoiceCommands.match("Check the calendars", commands: manifest.commands) == nil)
        let sendIt = ExtensionCommand(extension: "x", phrase: "send it", at: .end)
        #expect(VoiceCommands.match("Add it to the calendar send it", commands: manifest.commands + [sendIt])?.at == .end)
        #expect(await host.runCommand(match, app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify(text)])
        await host.stop()
    }

    @Test func generateSendsTheSchemaInOrderAndReturnsParsedJSON() async throws {
        try extensionFile("extract.ts", #"export default (voz) => voz.registerCommand("todo", async (e, ctx) => { const result = await ctx.generate({ prompt: e.text, schema: { type: "object", properties: { title: { type: "string" }, when: { type: "string", enum: ["today", "tomorrow"] }, items: { type: "array", items: { type: "string" } } }, required: ["title"] } }); ctx.notify(`${result.title} ${result.when} ${result.items.length}`) }, { at: "start" })"#)
        let actions = RecordedActions()
        let received = Mutex<GenerateParams?>(nil)
        let host = makeHost(actions: actions) { params in
            received.withLock { $0 = params }
            return #"{"title":"Call Milan","when":"tomorrow","items":["a","b"]}"#
        }
        _ = try await host.start()
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "todo", at: .start, text: "call Milan tomorrow"), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("Call Milan tomorrow 2")])
        let params = try #require(received.withLock { $0 })
        #expect(params.prompt == "call Milan tomorrow")
        #expect(params.schema.properties?.map(\.name) == ["title", "when", "items"])
        #expect(params.schema.properties?.map(\.optional) == [false, true, true])
        #expect(params.schema.properties?[1].schema.choices == ["today", "tomorrow"])
        #expect(params.schema.properties?[2].schema.items?.type == "string")
        _ = try ExtensionModel.dynamicSchema(params.schema, name: "Result")
        await host.stop()
    }

    @Test func askWaitsForTheUserPastTheCommandTimeout() async throws {
        try extensionFile("ask.ts", #"export default (voz) => voz.registerCommand({ phrase: "calendar", at: "start", async run(e, ctx) { const answer = await ctx.ask({ title: "Add to calendar?", fields: [{ id: "title", label: "Title", type: "text", value: e.text }, { id: "start", label: "Starts", type: "date", value: 1000 }], buttons: ["Copy", "Add"] }); ctx.notify(answer ? `${answer.button} ${answer.values.title} ${answer.values.start}` : "closed") } })"#)
        let actions = RecordedActions()
        let asked = Mutex<AskParams?>(nil)
        let host = makeHost(actions: actions, ask: { params in
            asked.withLock { $0 = params }
            try? await Task.sleep(for: .seconds(2))
            return AskAnswer(button: "Add", values: ["title": .string("Lunch"), "start": .number(2000)])
        })
        _ = try await host.start()
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "calendar", at: .start, text: "lunch"), app: app, timeout: .seconds(1)))
        #expect(actions.all == [.notify("Add Lunch 2000")])
        let params = try #require(asked.withLock { $0 })
        #expect(params.buttons == ["Copy", "Add"])
        #expect(params.fields.map(\.type) == [.text, .date])
        #expect(params.fields.first?.value == .string("lunch"))
        await host.stop()
    }

    @Test func busyWorkRunsPastTheCommandTimeout() async throws {
        try extensionFile("slow.ts", #"export default (voz) => voz.registerCommand({ phrase: "reply", at: "start", async run(e, ctx) { const text = await ctx.busy(async () => { await Bun.sleep(1500); return "done" }); ctx.notify(text) } })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "reply", at: .start, text: "x"), app: app, timeout: .seconds(1)))
        #expect(actions.all == [.busy("busy/1"), .idle("busy/1", succeeded: true), .notify("done")])
        await host.stop()
    }

    @Test func cancellingBusyWorkAbortsItsSignal() async throws {
        try extensionFile("slow.ts", #"export default (voz) => voz.registerAction({ id: "wait", name: "Wait", async run(ctx) { let aborted = false; const result = await ctx.busy((signal) => new Promise((resolve) => signal.addEventListener("abort", () => { aborted = true; resolve("late") }))); ctx.notify(`${result} ${aborted}`) } })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        let run = Task { await host.runAction("slow/wait", app: app, timeout: .seconds(5)) }
        while !actions.all.contains(.busy("busy/1")) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(await host.cancelBusy("busy/1", timeout: .seconds(2)))
        #expect(await run.value)
        #expect(actions.all.last == .notify("undefined true"))
        await host.stop()
    }

    @Test func failedBusyWorkEndsAndRejects() async throws {
        try extensionFile("slow.ts", #"export default (voz) => voz.registerAction({ id: "fail", name: "Fail", async run(ctx) { try { await ctx.busy(async () => { throw new Error("offline") }) } catch (error) { ctx.notify(error.message) } } })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await host.runAction("slow/fail", app: app, timeout: .seconds(2)))
        #expect(actions.all == [.busy("busy/1"), .idle("busy/1", succeeded: false), .notify("offline")])
        await host.stop()
    }

    @Test func actionsRewriteTheFocusedFieldThroughSelectAndInsert() async throws {
        try extensionFile("rewrite.ts", #"export default (voz) => voz.registerAction({ id: "shout", name: "Shout", async run(ctx) { const field = await ctx.field(); const selected = await ctx.select({ start: 0, length: field.text.length }); ctx.insert(`${field.text.toUpperCase()} ${field.selection.start} ${field.label} ${field.before} ${selected}`, { instruction: field.thread.title }) } })"#)
        let actions = RecordedActions()
        let selected = Mutex<TextRange?>(nil)
        let field = FocusedField(text: "hi tom", selection: TextRange(start: 3, length: 0), role: "AXTextArea", label: "Reply", window: nil, before: "Tom: lunch?", after: "",
                                 thread: makeThread("Tom"))
        let host = makeHost(actions: actions, field: { field }, select: { range in
            selected.withLock { $0 = range }
            return true
        })
        _ = try await host.start()
        #expect(await host.runAction("rewrite/shout", app: app, timeout: .seconds(2)))
        #expect(actions.all == [.insert(Insertion(text: "HI TOM 3 Reply Tom: lunch? true", source: "rewrite", instruction: "Tom"))])
        #expect(selected.withLock { $0 } == TextRange(start: 0, length: 6))
        await host.stop()
    }

    @Test func historyPassesTheQueryAndReturnsWhatYouWrote() async throws {
        try extensionFile("reply.ts", #"export default (voz) => voz.registerAction({ id: "read", name: "Read", async run(ctx) { const [first] = await voz.history({ thread: "T", source: "reply", limit: 2.5 }); ctx.notify(`${first.kind} ${first.text} ${first.outcome} ${first.thread ?? "none"} ${(await voz.history()).length}`) } })"#)
        let actions = RecordedActions()
        let queries = Mutex<[HistoryParams]>([])
        let host = makeHost(actions: actions, history: { params in
            queries.withLock { $0.append(params) }
            return [WrittenText(kind: .draft, text: "see you at 1", at: 1, thread: nil, source: "reply", instruction: nil, input: "", output: "See you at 1!", outcome: .edited)]
        })
        _ = try await host.start()
        #expect(await host.runAction("reply/read", app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("draft see you at 1 edited none 1")])
        let sent = queries.withLock { $0 }
        #expect(sent.map(\.thread) == ["T", nil])
        #expect(sent.map(\.source) == ["reply", nil])
        #expect(sent.map(\.limit) == [2, nil])
        await host.stop()
    }

    @Test func aListShowsWhatAnExtensionLearnedInTheBackground() async throws {
        try extensionFile("style.ts", #"""
            export default (voz) => {
              const rules = ["Short"];
              voz.registerList({ id: "style", title: "Writing style", items: () => rules.map((title, i) => ({ id: String(i), title })), remove: (id) => { rules.splice(Number(id), 1) } });
              voz.generate({ prompt: "learn", schema: { type: "object", properties: { rule: { type: "string" } } }, model: "on-device" }).then(({ rule }) => rules.push(rule));
            }
            """#)
        let models = Mutex<[String?]>([])
        let host = makeHost(generate: { params in
            models.withLock { $0.append(params.model) }
            return #"{"rule":"No greetings"}"#
        })
        let manifest = try await host.start()
        #expect(manifest.lists == [SettingsList(id: "style/style", title: "Writing style", description: "", removable: true, extension: "style")])
        var items: [SettingsListItem] = []
        for _ in 0..<100 where items.count < 2 {
            items = try await host.list("style/style", timeout: .seconds(2))
            if items.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(items.map(\.title) == ["Short", "No greetings"])
        #expect(models.withLock { $0 } == ["on-device"])
        #expect(try await host.list("style/style", remove: "0", timeout: .seconds(2)).map(\.title) == ["No greetings"])
        await host.stop()
    }

    @Test func browseKnowsWhichPackagesReadTheScreen() {
        #expect(manifestReadsScreen(#"{"name": "voz-reply", "voz": {"apiVersion": 8, "screen": true}}"#))
        #expect(!manifestReadsScreen(#"{"name": "voz-edit", "voz": {"apiVersion": 8}}"#))
        #expect(!manifestReadsScreen("not json"))
    }

    @Test func onlyPackagesThatAskCanReadTheScreen() async throws {
        let run = #"export default (voz) => voz.registerAction({ id: "read", name: "Read", async run(ctx) { try { const seen = await voz.screen(); ctx.notify(`${seen.app} ${seen.window} ${seen.text} ${seen.thread ?? "none"}`) } catch (error) { ctx.notify(error.message) } } })"#
        let reader = home.packages.appendingPathComponent("node_modules/voz-reader")
        try writeFile(#"{"name":"voz-reader","voz":{"apiVersion":8,"screen":true}}"#, named: "package.json", in: reader)
        try writeFile(run, named: "index.ts", in: reader)
        let other = home.packages.appendingPathComponent("node_modules/voz-other")
        try writeFile(#"{"name":"voz-other","voz":{"apiVersion":8}}"#, named: "package.json", in: other)
        try writeFile(run, named: "index.ts", in: other)
        let actions = RecordedActions()
        let reads = Mutex(0)
        let host = makeHost(packages: [reader.path, other.path], actions: actions, screen: {
            reads.withLock { $0 += 1 }
            return ScreenText(app: "Linear", window: "VOZ-12", thread: nil, text: "invoice export fails")
        })
        let manifest = try await host.start()
        #expect(manifest.screen == ["voz-reader"])
        #expect(await host.runAction("voz-reader/read", app: app, timeout: .seconds(2)))
        #expect(await host.runAction("voz-other/read", app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("Linear VOZ-12 invoice export fails none"), .notify(#"voz-other needs "screen": true under "voz" in its package.json to read the screen"#)])
        #expect(reads.withLock { $0 } == 1)
        await host.stop()
    }

    @Test func fieldIsNullWithoutAReadableTextField() async throws {
        try extensionFile("rewrite.ts", #"export default (voz) => voz.registerAction({ id: "read", name: "Read", async run(ctx) { ctx.notify(String(await ctx.field())) } })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await host.runAction("rewrite/read", app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("null")])
        await host.stop()
    }

    @Test func closingTheCardAnswersNull() async throws {
        try extensionFile("ask.ts", #"export default (voz) => voz.registerCommand({ phrase: "calendar", at: "start", async run(e, ctx) { const answer = await ctx.ask({ title: "Add?", buttons: ["Add"] }); ctx.notify(answer === null ? "closed" : "answered") } })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "calendar", at: .start, text: "x"), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("closed")])
        await host.stop()
    }

    @Test func generateFailuresRejectInsideTheExtension() async throws {
        try extensionFile("extract.ts", #"export default (voz) => voz.registerCommand("todo", async (e, ctx) => { try { await ctx.generate({ prompt: e.text, schema: { type: "object", properties: {} } }) } catch (error) { ctx.notify(error.message) } }, { at: "start" })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "todo", at: .start, text: "x"), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("The on-device model is unavailable: not in tests")])
        await host.stop()
    }

    @Test func generateRejectsRequiredNamesThatAreNotProperties() async throws {
        try extensionFile("extract.ts", #"export default (voz) => voz.registerCommand("todo", async (e, ctx) => { try { await ctx.generate({ prompt: e.text, schema: { type: "object", properties: { title: { type: "string" } }, required: ["titel"] } }) } catch (error) { ctx.notify(error.message) } }, { at: "start" })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "todo", at: .start, text: "x"), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify(#"Required property "titel" is not in properties"#)])
        await host.stop()
    }

    @Test func audioDropsTranscribeTheFileWithSpeakers() async throws {
        try extensionFile("notes.ts", #"export default (voz) => voz.on("audioDrop", async (e, ctx) => { const t = await ctx.transcribe(e.path, { speakers: true }); ctx.notify(`${e.path} ${t.speakers} ${t.turns.map((turn) => `${turn.speaker}:${turn.text}`).join("|")}`) })"#)
        let actions = RecordedActions()
        let received = Mutex<TranscribeFileParams?>(nil)
        let host = makeHost(actions: actions, transcribeFile: { params in
            received.withLock { $0 = params }
            return FileTranscript(text: "Hi. Hello.", seconds: 3, speakers: 2, turns: [
                SpeakerTurn(speaker: 1, start: 0, end: 1, text: "Hi."),
                SpeakerTurn(speaker: 2, start: 2, end: 3, text: "Hello."),
            ])
        })
        let manifest = try await host.start()
        #expect(manifest.subscribes(to: .audioDrop))
        #expect(await host.emit(.audioDrop(path: "/tmp/talk.mp3"), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("/tmp/talk.mp3 2 1:Hi.|2:Hello.")])
        #expect(received.withLock { $0 }.map { ($0.path, $0.speakers) } ?? ("", false) == ("/tmp/talk.mp3", true))
        await host.stop()
    }

    @Test func fileTranscriptionFailuresRejectInsideTheExtension() async throws {
        try extensionFile("notes.ts", #"export default (voz) => voz.on("audioDrop", async (e, ctx) => { try { await ctx.transcribe(e.path) } catch (error) { ctx.notify(error.message); throw error } })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await !host.emit(.audioDrop(path: "/tmp/talk.mp3"), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("Transcribing files needs a Parakeet speech model. Pick one in Settings")])
        await host.stop()
    }

    @Test func brokenOrHangingExtensionsAreReportedAndOthersStillLoad() async throws {
        try extensionFile("broken.ts", "export default (voz) => { syntax error here")
        try extensionFile("partial.ts", #"export default (voz) => { voz.on("beforeInsert", () => ({ text: "leaked" })); throw new Error("boom") }"#)
        try extensionFile("hang.ts", "export default async () => { await new Promise(() => {}) }")
        try extensionFile("noisy.ts", #"export default (voz) => { process.stdout.write("no newline"); console.log("loaded"); voz.on("beforeInsert", (e) => ({ text: e.text + "!" })) }"#)
        let distOnly = home.packages.appendingPathComponent("node_modules/voz-dist")
        try writeFile(#"{"name":"voz-dist","main":"dist/index.js"}"#, named: "package.json", in: distOnly)
        try writeFile("export default () => {}", named: "index.js", in: distOnly.appendingPathComponent("dist"))
        let pack = home.packages.appendingPathComponent("git/github.com/acme/voz-pack")
        try writeFile(#"{"name":"voz-pack","voz":{"extensions":["src/main.ts"]}}"#, named: "package.json", in: pack)
        try writeFile(#"export default (voz) => voz.on("beforeInsert", (e) => ({ text: e.text.toUpperCase() }))"#, named: "main.ts", in: pack.appendingPathComponent("src"))
        let malformed = home.packages.appendingPathComponent("node_modules/voz-malformed")
        try writeFile(#"{"name": "voz-malformed","#, named: "package.json", in: malformed)
        let host = makeHost(packages: [distOnly.path, malformed.path, pack.path])
        let manifest = try await host.start(timeout: .seconds(5))
        #expect(Set(manifest.extensions) == ["noisy", "voz-pack"])
        #expect(Set(manifest.errors.map(\.extension)) == ["broken", "partial", "hang", "voz-dist", "voz-malformed"])
        #expect(await host.beforeInsert(text: "hi", raw: "hi", app: app, timeout: .seconds(2)) == "HI!")
        await host.stop()
    }

    @Test func failingSlowOrBlockingHandlersNeverHoldUpDictation() async throws {
        try extensionFile("throws.ts", #"export default (voz) => voz.on("beforeInsert", () => { throw new Error("boom") })"#)
        try extensionFile("slow.ts", #"export default (voz) => voz.on("beforeInsert", () => new Promise(() => {}))"#)
        try extensionFile("sloppy.ts", #"export default (voz) => voz.on("afterInsert", () => { Promise.reject(new Error("sloppy")) })"#)
        try extensionFile("spin.ts", #"export default (voz) => voz.registerCommand("spin", () => { while (true) {} })"#)
        let host = makeHost()
        _ = try await host.start()
        #expect(await host.beforeInsert(text: "keep me", raw: "keep me", app: app, timeout: .milliseconds(200)) == "keep me")
        await host.emit(.afterInsert(text: "hi", raw: "hi"), app: app, timeout: .seconds(2))
        try await Task.sleep(for: .milliseconds(200))
        #expect(await host.ping(timeout: .seconds(2)))
        _ = await host.runCommand(VoiceCommandMatch(phrase: "spin", at: .end, text: ""), app: app, timeout: .milliseconds(100))
        #expect(await !host.ping(timeout: .milliseconds(300)))
        await host.stop()
    }

    @Test func expiredHandlersCannotSendActionsOrRunLaterHandlers() async throws {
        try extensionFile("a-late.ts", #"export default voz => voz.on("beforeInsert", async (event, ctx) => { await Bun.sleep(200); ctx.insert("late"); ctx.press("return"); ctx.notify("late"); return { text: "late" } })"#)
        try extensionFile("b-later.ts", #"export default voz => voz.on("beforeInsert", (event, ctx) => { ctx.insert("later handler"); return { text: event.text } })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await host.beforeInsert(text: "keep", raw: "keep", app: app, timeout: .milliseconds(50)) == "keep")
        try await Task.sleep(for: .milliseconds(350))
        #expect(await host.ping(timeout: .seconds(1)))
        #expect(actions.all.isEmpty)
        await host.stop()
    }

    @Test func malformedModelResultsUseFailureFallback() async throws {
        try extensionFile("bad.ts", #"export default voz => { voz.registerSpeechModel({ id: "bad", name: "Bad", transcribe: () => ({}) }); voz.registerCleanupModel({ id: "bad", name: "Bad", clean: () => ({ text: 42 }) }); voz.on("beforeInsert", () => ({ handled: false, text: "kept" })); }"#)
        let host = makeHost()
        _ = try await host.start()
        #expect(await host.transcribe(model: "bad/bad", path: "/tmp/test.wav", seconds: 1, app: app, timeout: .seconds(1)) == nil)
        #expect(await host.clean(model: "bad/bad", text: "hello", prompt: "", app: app, timeout: .seconds(1)) == nil)
        #expect(await host.beforeInsert(text: "hello", raw: "hello", app: app, timeout: .seconds(1)) == "kept")
        await host.stop()
    }

    @Test func blockedInputStillTimesOut() async throws {
        try extensionFile("spin.ts", #"export default voz => voz.registerCommand("spin", () => { while (true) {} })"#)
        let host = makeHost()
        _ = try await host.start()
        _ = await host.runCommand(VoiceCommandMatch(phrase: "spin", at: .end, text: ""), app: app, timeout: .seconds(1))
        let started = ContinuousClock.now
        let largeText = String(repeating: "long transcript ", count: 100_000)
        #expect(await host.beforeCleanup(CleanupPlan(prompt: largeText, mode: .heavy), app: app, timeout: .milliseconds(100)) == CleanupPlan(prompt: largeText, mode: .heavy))
        #expect(await !host.ping(timeout: .milliseconds(100)))
        // Sending a request larger than pipe capacity must not block the host actor.
        #expect(await !host.runCommand(VoiceCommandMatch(phrase: "spin", at: .end, text: largeText), app: app, timeout: .milliseconds(100)))
        #expect(ContinuousClock.now - started < .seconds(2))
        await host.stop()
    }

    @Test func stopKillsHostsThatIgnoreTermination() async throws {
        try extensionFile("stubborn.ts", #"import { writeFileSync } from "node:fs"; export default voz => { writeFileSync(voz.paths.data + "/pid", String(process.pid)); process.on("SIGTERM", () => {}); setInterval(() => {}, 1000); }"#)
        let host = makeHost()
        _ = try await host.start()
        let pid = try #require(fileContents(home.root.appendingPathComponent("data/stubborn/pid")).flatMap { Int32($0) })
        await host.stop()
        #expect(try await processIsGone(pid))
    }

    @Test func registeredModelsAndStepsAreNamespacedAndRun() async throws {
        try extensionFile("whisper.ts", #"export default (voz) => voz.registerSpeechModel({ id: "base", name: "Whisper", transcribe: (e, ctx) => ({ text: `${e.path} ${e.seconds} ${ctx.app.name}` }) })"#)
        try extensionFile("llm.ts", #"export default (voz) => { voz.registerCleanupModel({ id: "fast", name: "Fast LLM", clean: (e) => ({ text: `${e.text.toUpperCase()} (${e.prompt})` }) }); voz.registerCleanupStep({ id: "jira", name: "Jira keys", run: (e) => ({ text: e.text.replace(/jira (\d+)/, "JIRA-$1") }) }); voz.registerCleanupStep({ id: "keep", name: "Keeps text", run: () => {} }); voz.registerCleanupStep({ id: "boom", name: "Throws", run: () => { throw new Error("boom") } }) }"#)
        try extensionFile("nameless.ts", #"export default (voz) => voz.registerCleanupStep({ id: "x", run: (e) => e })"#)
        let host = makeHost()
        let manifest = try await host.start()
        #expect(manifest.speechModels == [HostComponent(id: "whisper/base", name: "Whisper")])
        #expect(manifest.cleanupModels == [HostComponent(id: "llm/fast", name: "Fast LLM")])
        #expect(manifest.cleanupSteps.map(\.id) == ["llm/jira", "llm/keep", "llm/boom"])
        #expect(manifest.errors.map(\.extension) == ["nameless"])
        #expect(await host.transcribe(model: "whisper/base", path: "/tmp/a.wav", seconds: 2, app: app, timeout: .seconds(2)) == "/tmp/a.wav 2 Slack")
        #expect(await host.clean(model: "llm/fast", text: "hi", prompt: "Clean.", app: app, timeout: .seconds(2)) == "HI (Clean.)")
        #expect(await host.cleanupStep("llm/jira", text: "see jira 12", app: app, timeout: .seconds(2)) == "see JIRA-12")
        #expect(await host.cleanupStep("llm/keep", text: "same", app: app, timeout: .seconds(2)) == "same")
        #expect(await host.cleanupStep("llm/boom", text: "x", app: app, timeout: .seconds(2)) == nil)
        #expect(await host.transcribe(model: "missing/model", path: "/tmp/a.wav", seconds: 1, app: app, timeout: .seconds(2)) == nil)
        await host.stop()
    }

    @Test func actionsRunByIdAndSettingsFallBackToDefaults() async throws {
        try writeFile(#"{"config":{"jira":{"project":"WEB","count":"three","mode":"loud"}}}"#, named: "settings.json", in: home.root)
        try extensionFile("jira.ts", #"export default (voz) => { const s = voz.settings({ project: { type: "string", title: "Project", default: "VOZ" }, count: { type: "number", title: "Count", default: 2 }, mode: { type: "string", title: "Mode", default: "quiet", options: ["quiet", "casual"] }, on: { type: "boolean", title: "On", default: true } }); voz.registerAction({ id: "open", name: "Open board", hotkey: "ctrl+opt+j", run: (ctx) => ctx.notify(`${s.project} ${s.count} ${s.mode} ${s.on} ${ctx.app.name}`) }) }"#)
        try extensionFile("typo.ts", #"export default (voz) => voz.settings({ project: { type: "text", title: "Project", default: "" } })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        let manifest = try await host.start()
        #expect(manifest.actions.map(\.id) == ["jira/open"])
        #expect(manifest.actions.first?.hotkey == "ctrl+opt+j")
        #expect(manifest.settings.map(\.extension) == ["jira"])
        #expect(manifest.settings.first?.fields.map(\.key) == ["project", "count", "mode", "on"])
        #expect(manifest.settings.first?.fields.map(\.default) == [.string("VOZ"), .number(2), .string("quiet"), .boolean(true)])
        #expect(manifest.errors.map(\.extension) == ["typo"])
        #expect(await host.runAction("jira/open", app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("WEB 2 quiet true Slack")])
        #expect(await host.runAction("jira/missing", app: app, timeout: .seconds(2)) == false)
        await host.stop()
    }

    @Test func toolsTakeTypedInputAndReturnJSON() async throws {
        try extensionFile("jira.ts", #"export default (voz) => { voz.registerTool({ id: "issues", description: "List issues", readOnly: true, input: { type: "object", properties: { project: { type: "string" }, limit: { type: "integer" } }, required: ["project"] }, positional: ["project"], run: (input, ctx) => ({ issues: [`${input.project}-${input.limit ?? 1}`], app: ctx.app.name }) }); voz.registerTool({ id: "ping", description: "Ping", run: () => {} }); voz.registerTool({ id: "boom", description: "Fails", run: () => { throw new Error("Jira is down") } }) }"#)
        try extensionFile("bad.ts", #"export default (voz) => voz.registerTool({ id: "x", description: "Bad", input: { type: "object", properties: {}, required: ["missing"] }, run: () => 1 })"#)
        try extensionFile("typo.ts", #"export default (voz) => voz.registerTool({ id: "x", description: "Typo", input: { type: "object", properties: { key: { type: "string" } } }, positional: ["kee"], run: () => 1 })"#)
        let host = makeHost()
        let manifest = try await host.start()
        #expect(manifest.tools.map(\.id) == ["jira/issues", "jira/ping", "jira/boom"])
        #expect(manifest.tools.first?.readOnly == true)
        #expect(manifest.tools.first?.input.properties?.map(\.name) == ["project", "limit"])
        #expect(manifest.tools.first?.positional == ["project"])
        #expect(manifest.tools.last?.positional == [])
        #expect(manifest.errors.map(\.extension).sorted() == ["bad", "typo"])
        let issues = try await host.runTool("jira/issues", input: ["project": "VOZ", "limit": 3], app: app, timeout: .seconds(2))
        #expect(issues == .object(["issues": .array(["VOZ-3"]), "app": "Slack"]))
        #expect(try await host.runTool("jira/ping", input: [:], app: app, timeout: .seconds(2)) == .null)
        await #expect(throws: ControlError.failed("Jira is down")) { try await host.runTool("jira/boom", input: [:], app: app, timeout: .seconds(2)) }
        await host.stop()
    }

    @Test func activitiesShowUntilTheyEndOrTheUserStopsThem() async throws {
        try extensionFile("meeting.ts", #"export default (voz) => { voz.startActivity({ title: "Sync", since: 500 }).end(); voz.startActivity({ title: "Recording meeting", since: 1000, stop: (ctx) => ctx.notify("stopped") }) }"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await host.stopActivity("meeting/2", app: app, timeout: .seconds(2)))
        #expect(await host.stopActivity("meeting/2", app: app, timeout: .seconds(2)) == false)
        #expect(actions.all == [
            startedActivity("meeting/1", "Sync", since: 0.5, stoppable: false),
            .endActivity("meeting/1"),
            startedActivity("meeting/2", "Recording meeting", since: 1, stoppable: true),
            .endActivity("meeting/2"),
            .notify("stopped"),
        ])
        await host.stop()
    }

    @Test func openingAnActivityShowsANoteThatReportsEdits() async throws {
        try extensionFile("meeting.ts", #"export default (voz) => { voz.startActivity({ title: "Meeting", since: 1000, open(ctx) { const note = ctx.openNote({ title: "Meeting", text: "Agenda", onChange(text) { voz.addHistory({ text }); note.close() } }) } }) }"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(await host.openActivity("meeting/1", app: app, timeout: .seconds(2)))
        #expect(await host.noteChanged("note/1", text: "Ship it", timeout: .seconds(2)))
        #expect(await host.noteChanged("note/1", text: "Closed", timeout: .seconds(2)))
        #expect(await host.openActivity("meeting/2", app: app, timeout: .seconds(2)) == false)
        #expect(actions.all == [
            startedActivity("meeting/1", "Meeting", since: 1, stoppable: false, openable: true),
            .openNote(ExtensionNote(id: "note/1", title: "Meeting", text: "Agenda")),
            .addHistory(ExtensionHistoryEntry(extension: "meeting", text: "Ship it", seconds: 0, file: nil)),
            .closeNote("note/1"),
        ])
        await host.stop()
    }

    @Test func activitiesTranscribeLiveUntilTheyStop() async throws {
        try extensionFile("meeting.ts", #"export default (voz) => { let live; const activity = voz.startActivity({ title: "Meeting", since: 1000, async stop(ctx) { const t = await live.stop(); ctx.notify(`${t.speakers} ${t.text}`) } }); voz.registerAction({ id: "listen", name: "Listen", async run() { live = await activity.transcribeLive({ systemAudio: true, speakers: true, onTranscript: (t) => voz.addHistory({ text: `${t.speakers}:${t.text}` }) }) } }) }"#)
        let actions = RecordedActions()
        let started = Mutex<LiveStartParams?>(nil)
        let host = makeHost(
            actions: actions,
            startLive: { params, onTranscript in
                started.withLock { $0 = params }
                await onTranscript(FileTranscript(text: "Hi.", seconds: 1, speakers: 1, turns: [SpeakerTurn(speaker: 1, start: 0, end: 1, text: "Hi.")]))
            },
            stopLive: { _ in FileTranscript(text: "Hi.", seconds: 1, speakers: 1, turns: [SpeakerTurn(speaker: 1, start: 0, end: 1, text: "Hi.")]) }
        )
        _ = try await host.start()
        #expect(await host.runAction("meeting/listen", app: app, timeout: .seconds(2)))
        #expect(await host.stopActivity("meeting/1", app: app, timeout: .seconds(2)))
        #expect(started.withLock { $0 }.map { [$0.session, $0.activity, "\($0.speakers)", "\($0.systemAudio)"] } == ["live/1", "meeting/1", "true", "true"])
        #expect(actions.all == [
            startedActivity("meeting/1", "Meeting", since: 1, stoppable: true),
            .addHistory(ExtensionHistoryEntry(extension: "meeting", text: "1:Hi.", seconds: 0, file: nil)),
            .endActivity("meeting/1"),
            .notify("1 Hi."),
        ])
        await host.stop()
    }

    @Test func extensionsAddEntriesToTheHistory() async throws {
        try extensionFile("meeting.ts", #"export default (voz) => { voz.addHistory({ text: "hello team", seconds: 3, file: "/tmp/meeting.md" }); voz.addHistory({ text: "short" }) }"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        _ = try await host.start()
        #expect(actions.all == [
            .addHistory(ExtensionHistoryEntry(extension: "meeting", text: "hello team", seconds: 3, file: "/tmp/meeting.md")),
            .addHistory(ExtensionHistoryEntry(extension: "meeting", text: "short", seconds: 0, file: nil)),
        ])
        await host.stop()
    }

    @Test func sharedHotkeyRunsTheSelectionActionWithASelection() {
        let reply = ExtensionAction(id: "reply/reply", name: "Reply", hotkey: "rightopt", hidden: false, extension: "reply")
        let edit = ExtensionAction(id: "edit/edit", name: "Edit", hotkey: "rightopt", hidden: false, extension: "edit", when: .selection)
        #expect(ExtensionAction.pick([edit, reply], hasSelection: true) == edit)
        #expect(ExtensionAction.pick([edit, reply], hasSelection: false) == reply)
        #expect(ExtensionAction.pick([edit], hasSelection: false) == edit)
        #expect(reply.hotkeyLabel == "Right ⌥")
        #expect(Hotkey.tap(named: "RightOpt")?.keyCode == 61)
        #expect(Hotkey.tap(named: "opt") == nil)
    }

    @Test func hiddenActionsLeaveThePanelAndUpdatesReachVoz() async throws {
        try extensionFile("setup.ts", #"export default (voz) => { const done = voz.registerAction({ id: "done", name: "Done", hidden: true, run() {} }); const connect = voz.registerAction({ id: "connect", name: "Connect", hotkey: "ctrl+opt+t", run() { connect.update({ hidden: true }); done.update({ hidden: false }) } }) }"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        let manifest = try await host.start()
        #expect(manifest.actions == [
            ExtensionAction(id: "setup/done", name: "Done", hotkey: nil, hidden: true, extension: "setup"),
            ExtensionAction(id: "setup/connect", name: "Connect", hotkey: "ctrl+opt+t", hidden: false, extension: "setup"),
        ])
        #expect(await host.runAction("setup/connect", app: app, timeout: .seconds(2)))
        #expect(actions.all.last == .actions([
            ExtensionAction(id: "setup/done", name: "Done", hotkey: nil, hidden: false, extension: "setup"),
            ExtensionAction(id: "setup/connect", name: "Connect", hotkey: "ctrl+opt+t", hidden: true, extension: "setup"),
        ]))
        await host.stop()
    }

    @Test func newExtensionTemplateLoadsAndRuns() async throws {
        let folder = try ExtensionTemplate.create(named: "voz-hello", in: home.root, from: extensionResources)
        let apiVersion = try ExtensionTemplate.apiVersion(in: extensionResources)
        #expect(fileContents(folder.appendingPathComponent("package.json"))?.contains(#""apiVersion": \#(apiVersion) }"#) == true)
        #expect(fileContents(folder.appendingPathComponent("AGENTS.md"))?.contains(VozHome.skillName) == true)
        #expect(fileContents(folder.appendingPathComponent(".claude/skills/voz-extension/SKILL.md")) != nil)
        let actions = RecordedActions()
        let host = makeHost(packages: [folder.path], actions: actions)
        let manifest = try await host.start()
        #expect(manifest.errors.isEmpty)
        #expect(manifest.commands.map(\.phrase) == ["say hello"])
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "say hello", at: .end, text: ""), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("Hello from voz-hello")])
        await host.stop()
    }

    @Test func disabledExtensionsDoNotLoadAndNewerApiPackagesLoadUntilTheyCallSomethingMissing() async throws {
        try writeFile(#"{"disabled":["off","pack"]}"#, named: "settings.json", in: home.root)
        try extensionFile("on.ts", #"import { apiVersion } from "voz"; export default (voz) => voz.on("beforeInsert", (e) => ({ text: `${e.text} ${apiVersion}` }))"#)
        try extensionFile("off.ts", #"export default (voz) => voz.on("beforeInsert", () => ({ text: "off ran" }))"#)
        let pack = home.packages.appendingPathComponent("node_modules/pack")
        try writeFile(#"{"name":"pack"}"#, named: "package.json", in: pack)
        try writeFile(#"export default (voz) => voz.on("beforeInsert", () => ({ text: "pack ran" }))"#, named: "index.ts", in: pack.appendingPathComponent("extensions/a"))
        let future = home.packages.appendingPathComponent("node_modules/future")
        try writeFile(#"{"name":"future","voz":{"apiVersion":9}}"#, named: "package.json", in: future)
        try writeFile("export default (voz) => { if (voz.registerWidget) voz.registerWidget({}) }", named: "index.ts", in: future)
        let needy = home.packages.appendingPathComponent("node_modules/needy")
        try writeFile(#"{"name":"needy","voz":{"apiVersion":9}}"#, named: "package.json", in: needy)
        try writeFile("export default (voz) => voz.registerWidget({})", named: "index.ts", in: needy)
        let host = makeHost(packages: [pack.path, future.path, needy.path])
        let manifest = try await host.start()
        #expect(manifest.extensions == ["on", "future"])
        #expect(manifest.errors.map(\.extension) == ["needy"])
        #expect(manifest.errors.first?.message.contains("written for Voz extension API 9, this Voz has 8. Update Voz.") == true)
        #expect(await host.beforeInsert(text: "hi", raw: "hi", app: app, timeout: .seconds(2)) == "hi 8")
        await host.stop()
    }

    @Test func apiVersionOnePackagesKeepTheApiTheyWereWrittenFor() async throws {
        try writeFile(#"{"config":{"old":{"suffix":"!"}}}"#, named: "settings.json", in: home.root)
        try extensionFile("say.ts", #"export default (voz) => voz.on("beforeInsert", (e) => { voz.events.emit("seen", e.text) })"#)
        let old = home.packages.appendingPathComponent("node_modules/old")
        try writeFile(#"{"name":"old","voz":{"apiVersion":1}}"#, named: "package.json", in: old)
        try writeFile(#"export default (voz) => { let seen = ""; voz.events.on("seen", (t) => { seen = t }); voz.log("loaded"); voz.on("beforeInsert", () => seen === "stop" ? { handled: true } : { text: `${seen}${voz.config.suffix} ${typeof voz.paths.home}` }) }"#, named: "index.ts", in: old)
        let new = home.packages.appendingPathComponent("node_modules/new")
        try writeFile(#"{"name":"new","voz":{"apiVersion":2}}"#, named: "package.json", in: new)
        try writeFile(#"export default (voz) => voz.on("beforeInsert", (e) => ({ text: `${e.text} ${typeof voz.events}` }))"#, named: "index.ts", in: new)
        let host = makeHost(packages: [old.path, new.path])
        let manifest = try await host.start()
        #expect(manifest.errors.isEmpty)
        #expect(manifest.extensions == ["say", "old", "new"])
        #expect(await host.beforeInsert(text: "hi", raw: "hi", app: app, timeout: .seconds(2)) == "hi! string undefined")
        #expect(await host.beforeInsert(text: "stop", raw: "stop", app: app, timeout: .seconds(2)) == "")
        await host.stop()
    }

    @Test func apiVersionFourPackagesUseCommandObjectsAndAfterRecording() async throws {
        let current = home.packages.appendingPathComponent("node_modules/current")
        try writeFile(#"{"name":"current","voz":{"apiVersion":4}}"#, named: "package.json", in: current)
        try writeFile(#"export default (voz) => { voz.registerCommand({ phrase: "todo", at: "start", run: (e, ctx) => ctx.notify(`todo ${e.text}`) }); voz.on("afterRecording", (e, ctx) => ctx.notify(`heard ${e.seconds}`)) }"#, named: "index.ts", in: current)
        let positional = home.packages.appendingPathComponent("node_modules/positional")
        try writeFile(#"{"name":"positional","voz":{"apiVersion":4}}"#, named: "package.json", in: positional)
        try writeFile(#"export default (voz) => voz.registerCommand("todo", () => {})"#, named: "index.ts", in: positional)
        let renamed = home.packages.appendingPathComponent("node_modules/renamed")
        try writeFile(#"{"name":"renamed","voz":{"apiVersion":4}}"#, named: "package.json", in: renamed)
        try writeFile(#"export default (voz) => voz.on("recording", () => {})"#, named: "index.ts", in: renamed)
        let actions = RecordedActions()
        let host = makeHost(packages: [current.path, positional.path, renamed.path], actions: actions)
        let manifest = try await host.start()
        #expect(manifest.extensions == ["current"])
        #expect(manifest.errors.map(\.extension) == ["positional", "renamed"])
        #expect(manifest.errors.first?.message.contains("registerCommand needs { phrase, run }") == true)
        #expect(manifest.errors.last?.message.contains(#"Unknown event "recording""#) == true)
        #expect(manifest.subscribes(to: .afterRecording))
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "todo", at: .start, text: "call Milan"), app: app, timeout: .seconds(2)))
        #expect(await host.emit(.afterRecording(path: "/tmp/a.wav", seconds: 2), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("todo call Milan"), .notify("heard 2")])
        await host.stop()
    }

    @Test func apiVersionThreePackagesKeepPositionalCommandsAndTheRecordingEvent() async throws {
        let old = home.packages.appendingPathComponent("node_modules/old")
        try writeFile(#"{"name":"old","voz":{"apiVersion":3}}"#, named: "package.json", in: old)
        try writeFile(#"export default (voz) => { voz.registerCommand("todo", (e, ctx) => ctx.notify(`todo ${e.text}`), { at: "start" }); voz.registerCommand({ phrase: "send it", run: (e, ctx) => ctx.press("return") }); voz.on("recording", (e, ctx) => ctx.notify(`heard ${e.seconds}`)) }"#, named: "index.ts", in: old)
        let actions = RecordedActions()
        let host = makeHost(packages: [old.path], actions: actions)
        let manifest = try await host.start()
        #expect(manifest.errors.isEmpty)
        #expect(manifest.subscribes(to: .afterRecording))
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "todo", at: .start, text: "call Milan"), app: app, timeout: .seconds(2)))
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "send it", at: .end, text: ""), app: app, timeout: .seconds(2)))
        #expect(await host.emit(.afterRecording(path: "/tmp/a.wav", seconds: 2), app: app, timeout: .seconds(2)))
        #expect(actions.all == [.notify("todo call Milan"), .press("return"), .notify("heard 2")])
        await host.stop()
    }

    @Test func contextCallsAfterTheHandlerFinishedAreLogged() async throws {
        try extensionFile("late.ts", #"export default (voz) => voz.registerCommand({ phrase: "later", run: (e, ctx) => { setTimeout(() => ctx.notify("late"), 50) } })"#)
        let actions = RecordedActions()
        let logs = RecordedLogs()
        let host = makeHost(actions: actions, logs: logs)
        _ = try await host.start()
        #expect(await host.runCommand(VoiceCommandMatch(phrase: "later", at: .end, text: ""), app: app, timeout: .seconds(2)))
        #expect(try await logs.waitFor { $0.contains("Dropped ctx.notify") })
        #expect(actions.all.isEmpty)
        await host.stop()
    }

    @Test func hostProcessNeverOutlivesVoz() async throws {
        try extensionFile("timer.ts", "export default () => { setInterval(() => {}, 1000) }")
        #expect(try await !hostOutlivesClosedInput(home: home))

        try writeFile(#"import { writeFileSync } from "node:fs"; writeFileSync(JSON.parse(process.argv[2]).home + "/pid", String(process.pid)); setInterval(() => {}, 1000)"#, named: "stuck.ts", in: home.root)
        let script = home.root.appendingPathComponent("stuck.ts")
        let host = ExtensionHost(launch: .init(bun: installedBun!, script: script, home: home, packageDirectories: []), onAction: { _ in }, onLog: { _ in }, onExit: { _ in })
        await #expect(throws: ExtensionHostError.startTimedOut) { try await host.start(timeout: .seconds(1)) }
        let pid = try #require(fileContents(home.root.appendingPathComponent("pid")).flatMap { Int32($0) })
        #expect(try await processIsGone(pid))
    }
}

@Suite struct VozHomeTests {
    @Test func pipelineChoicesDefaultRoundTripAndKeepOtherSettings() throws {
        let home = temporaryHome()
        #expect(try home.pipelineChoices() == .standard)
        try home.setPackageSources(["npm:voz-a"])
        let before = try home.extensionSettings()
        let choices = PipelineChoices(speechModel: "whisper/base", cleanupModel: "llm/fast", cleanupSteps: ["llm/jira", "model"])
        try home.setPipelineChoices(choices)
        #expect(try home.pipelineChoices() == choices)
        #expect(try home.packageSources() == ["npm:voz-a"])
        #expect(try home.extensionSettings() == before)
    }

    @Test func retiredRuleStepsDropOutOfOlderSettings() throws {
        let home = temporaryHome()
        try writeFile(#"{"cleanupSteps":["fillers","punctuation","llm/jira","dictionary","model"]}"#, named: "settings.json", in: home.root)
        #expect(try home.pipelineChoices().cleanupSteps == ["llm/jira", "model"])
    }

    @Test func configRoundTripsTypedValuesAndKeepsOtherSettings() throws {
        let home = temporaryHome()
        try writeFile(#"{"packages":["npm:voz-jira"],"config":{"jira":{"project":"VOZ","nested":{"a":1}},"other":{"x":1}}}"#, named: "settings.json", in: home.root)
        try home.setConfig(.number(3), key: "count", for: "jira")
        try home.setConfig(.boolean(false), key: "on", for: "jira")
        try home.setConfig(.string("WEB"), key: "project", for: "jira")
        #expect(posixPermissions(home.root) == 0o700)
        #expect(posixPermissions(home.settings) == 0o600)
        #expect(try home.config(for: "jira") == ["project": .string("WEB"), "count": .number(3), "on": .boolean(false)])
        #expect(try home.config(for: "other") == ["x": .number(1)])
        #expect(try home.config(for: "missing") == [:])
        #expect(try home.packageSources() == ["npm:voz-jira"])
    }

    @Test func authoringFilesGiveEveryAgentTheExtensionSkill() throws {
        let home = temporaryHome()
        try home.writeAuthoringFiles(from: extensionResources)
        try home.writeAuthoringFiles(from: extensionResources)
        let skill = extensionResources.appendingPathComponent("voz-extension")
        for agentFolder in [".claude", ".agents"] {
            for file in ["SKILL.md", "references/api.md"] {
                let installed = home.root.appendingPathComponent("\(agentFolder)/skills/voz-extension/\(file)")
                #expect(fileContents(installed) == fileContents(skill.appendingPathComponent(file)))
            }
        }
        #expect(fileContents(home.root.appendingPathComponent("CLAUDE.md")) == "@AGENTS.md\n")
        #expect(fileContents(home.root.appendingPathComponent("AGENTS.md")) == fileContents(extensionResources.appendingPathComponent("AGENTS.md")))
    }

    @Test func skillInstallsForEveryAgentInTheHomeFolder() throws {
        let userHome = temporaryHome().root
        try VozHome.writeSkill(into: userHome, from: extensionResources)
        try VozHome.writeSkill(into: userHome, from: extensionResources)
        for agentFolder in [".claude", ".agents"] {
            let installed = userHome.appendingPathComponent("\(agentFolder)/skills/voz-extension/SKILL.md")
            #expect(fileContents(installed) == fileContents(extensionResources.appendingPathComponent("voz-extension/SKILL.md")))
        }
        #expect(fileContents(userHome.appendingPathComponent("AGENTS.md")) == nil)
    }

    @Test func skillNameMatchesItsFolderAndTheBuildPrompt() {
        let skill = fileContents(extensionResources.appendingPathComponent("\(VozHome.skillName)/SKILL.md"))
        #expect(skill?.hasPrefix("---\nname: \(VozHome.skillName)\n") == true)
        #expect(ExtensionsModel.buildPrompt.contains("the \(VozHome.skillName) skill"))
    }

    @Test func installedPackagesReadTheirDescription() throws {
        let home = temporaryHome()
        let package = home.root.appendingPathComponent("voz-things3")
        try writeFile(#"{"name":"voz-things3","version":"0.1.0","description":"Say todo to add a to-do"}"#, named: "package.json", in: package)
        try home.setPackageSources([package.path])
        #expect(try home.installedExtensions() == [InstalledExtension(name: "voz-things3", source: localSource(package.path), version: "0.1.0", description: "Say todo to add a to-do")])
    }

    @Test func historyShowsTheIconAPackageDeclares() throws {
        let home = temporaryHome()
        let meeting = home.root.appendingPathComponent("voz-meeting")
        let broken = home.root.appendingPathComponent("voz-broken")
        try writeFile(#"{"name":"voz-meeting","voz":{"icon":"file-volume"}}"#, named: "package.json", in: meeting)
        try writeFile(#"{"name":"voz-broken","voz":{"icon":"not-an-icon"}}"#, named: "package.json", in: broken)
        try home.setPackageSources([meeting.path, broken.path])
        let installed = try home.installedExtensions()
        #expect(ExtensionsModel.historyIcon(for: "voz-meeting", in: installed) == .fileVolume)
        #expect(ExtensionsModel.historyIcon(for: "voz-meeting/record", in: installed) == .fileVolume)
        #expect(ExtensionsModel.historyIcon(for: "voz-meetings", in: installed) == .puzzle)
        #expect(ExtensionsModel.historyIcon(for: "voz-broken", in: installed) == .puzzle)
    }
}

@Test func typesDeclareTheApiVersionTheHostRuns() throws {
    #expect(try ExtensionTemplate.apiVersion(in: extensionResources) == hostApiVersion())
}

@Test func administratorScriptQuotesAnyAppPath() {
    let script = CommandLineTool.administratorScript(linking: #"/Users/a "b" 'c'\d/voz.app/Contents/MacOS/voz"#)
    #expect(compilesAsAppleScript(script))
    #expect(script.contains(#"'/Users/a \"b\" '\\''c'\\''\\d/voz.app/Contents/MacOS/voz'"#))
}

@Test func displayNamesDropTheVozPrefix() {
    #expect(ExtensionsModel.displayName("voz-apple-calendar") == "Apple Calendar")
    #expect(ExtensionsModel.displayName("voz-things3") == "Things3")
    #expect(ExtensionsModel.displayName("voz-mcp") == "MCP")
    #expect(ExtensionsModel.displayName("@joel/voz-transcribe-file") == "Transcribe File")
    #expect(ExtensionsModel.displayName("notes") == "Notes")
}

@Test func gitSourcesRejectDotHostsThatEscapeTheGitFolder() throws {
    #expect(try parseSource("git:github.com/me/repo") == .git(host: "github.com", path: "me/repo", ref: nil))
    for raw in ["git:../me/repo", "git:./me/repo", "https://../me/repo"] {
        #expect(throws: PackageSourceError.unrecognized(raw)) { try parseSource(raw) }
    }
}

struct FieldContextTests {
    /// 0 window ─ 1 thread [2 "Tom: lunch?", 3 "Ana: 12?"] ─ 4 composer [5 field, 6 "Send"] ─ 7 footer [8 "Draft saved", 9 text area "notes" [10 "notes"]]
    private let children: [Int: [Int]] = [0: [1, 4, 7], 1: [2, 3], 4: [5, 6], 7: [8, 9], 9: [10]]
    private let text: [Int: String] = [2: "Tom: lunch?", 3: "Ana: 12?", 6: "Send", 8: "Draft saved", 9: "notes", 10: "notes"]

    private func parent(_ node: Int) -> Int? {
        children.first { $0.value.contains(node) }?.key
    }

    @Test func readsSiblingsOutwardInScreenOrder() {
        let around = FieldReader.surroundingText(of: 5, parent: parent, children: { children[$0] ?? [] }, text: { text[$0] })
        #expect(around.before == "Tom: lunch?\nAna: 12?")
        #expect(around.after == "Send\nDraft saved\nnotes")
    }

    @Test func keepsTheTextNearestTheField() {
        let around = FieldReader.surroundingText(of: 5, limits: (before: 8, after: 6), parent: parent, children: { children[$0] ?? [] }, text: { text[$0] })
        #expect(around.before == "Ana: 12?")
        #expect(around.after == "Send\nD")
    }
}

struct FocusedWebsiteTests {
    @Test func keepsOnlyTheHostnameOfWebPages() {
        #expect(FocusedWebsite.hostname(from: "https://GitHub.com/Joelheile/voz/pull/52?tab=files") == "github.com")
        #expect(FocusedWebsite.hostname(from: "http://localhost:3000/") == "localhost")
        #expect(FocusedWebsite.hostname(from: "file:///Users/me/notes.html") == nil)
        #expect(FocusedWebsite.hostname(from: "about:blank") == nil)
        #expect(FocusedWebsite.hostname(from: nil) == nil)
        #expect(FocusedWebsite.hostname(from: "https://example.com./") == "example.com")
    }

    @Test func outermostPageWinsOverItsIframes() {
        // Focus in an embedded widget, inside a typing iframe like Google Docs uses, inside the page
        let chain: [String?] = ["https://widget.example.net/embed", "about:blank", nil, "https://docs.google.com/document/d/1", nil]
        #expect(FocusedWebsite.hostname(from: 0, parent: { $0 + 1 < chain.count ? $0 + 1 : nil }, webAreaURL: { chain[$0] }) == "docs.google.com")
        #expect(FocusedWebsite.hostname(from: 0, parent: { _ in nil }, webAreaURL: { _ in nil }) == nil)
    }
}
