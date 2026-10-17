import Testing
@testable import VozCore

@Suite(.enabled(if: installedBun != nil, "Needs Bun at ~/.bun/bin/bun or BUN_PATH"))
struct ExtensionHostTests {
    private let home = temporaryHome()
    private let app = HostApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")

    private func extensionFile(_ name: String, _ source: String) throws {
        try writeFile(source, named: name, in: home.extensions)
    }

    private func makeHost(packages: [String] = [], actions: RecordedActions = RecordedActions()) -> ExtensionHost {
        ExtensionHost(
            launch: .init(bun: installedBun!, script: hostScript, home: home, packageDirectories: packages.map(fileURL)),
            onAction: { actions.append($0) },
            onLog: { _ in },
            onExit: { _ in }
        )
    }

    @Test func beforeInsertHandlersChainInLoadOrder() async throws {
        try extensionFile("a-upper.ts", #"export default (voz) => voz.on("beforeInsert", (e) => ({ text: e.text.toUpperCase() }))"#)
        try extensionFile("b-bang.ts", #"export default (voz) => voz.on("beforeInsert", (e) => ({ text: e.text + "!" }))"#)
        let host = makeHost()
        let manifest = try await host.start()
        #expect(manifest.extensions == ["a-upper", "b-bang"])
        #expect(manifest.events == ["beforeInsert"])

        #expect(await host.beforeInsert(text: "hi there", raw: "hi there", app: app, timeout: .seconds(2)) == "HI THERE!")
        await host.stop()
    }

    @Test func handlersSeeAppAndConfig() async throws {
        try writeFile(#"{"config":{"tag":{"suffix":" #voz"}}}"#, named: "settings.json", in: home.root)
        try extensionFile("tag.ts", #"export default (voz) => voz.on("beforeInsert", (e) => ({ text: `${e.text} [${e.app.name}]${voz.config.suffix}` }))"#)
        let host = makeHost()
        _ = try await host.start()
        #expect(await host.beforeInsert(text: "hi", raw: "hi", app: app, timeout: .seconds(2)) == "hi [Slack] #voz")
        await host.stop()
    }

    @Test func failingOrSlowHandlersKeepTheText() async throws {
        try extensionFile("throws.ts", #"export default (voz) => voz.on("beforeInsert", () => { throw new Error("boom") })"#)
        try extensionFile("slow.ts", #"export default (voz) => voz.on("beforeInsert", () => new Promise(() => {}))"#)
        let host = makeHost()
        _ = try await host.start()
        #expect(await host.beforeInsert(text: "keep me", raw: "keep me", app: app, timeout: .milliseconds(200)) == "keep me")
        await host.stop()
    }

    @Test func brokenExtensionIsReportedAndOthersStillLoad() async throws {
        try extensionFile("broken.ts", "export default (voz) => { syntax error here")
        try extensionFile("fine.ts", #"export default (voz) => voz.on("beforeInsert", () => ({ text: "fine" }))"#)
        let host = makeHost()
        let manifest = try await host.start()
        #expect(manifest.extensions == ["fine"])
        #expect(manifest.errors.count == 1)
        #expect(manifest.errors.first?.hasPrefix("broken") == true)
        await host.stop()
    }

    @Test func commandsRunAndSendActions() async throws {
        try extensionFile("send.ts", #"export default (voz) => voz.registerCommand("send it", async (ctx) => { ctx.insert(`[${ctx.text}]`); ctx.press("cmd+return") })"#)
        let actions = RecordedActions()
        let host = makeHost(actions: actions)
        let manifest = try await host.start()
        #expect(manifest.commands == ["send it"])

        #expect(await host.runCommand(phrase: "send it", text: "hello", app: app, timeout: .seconds(2)))
        #expect(actions.all == [.insert("[hello]"), .press("cmd+return")])
        await host.stop()
    }

    @Test func packagesLoadFromManifestAndConsoleLogDoesNotBreakProtocol() async throws {
        let package = home.packages.appendingPathComponent("git/github.com/acme/voz-pack")
        try writeFile(#"{"name":"voz-pack","voz":{"extensions":["src/main.ts"]}}"#, named: "package.json", in: package)
        try writeFile(#"export default (voz) => { console.log("loaded"); voz.on("beforeInsert", (e) => ({ text: e.text.trim() })) }"#, named: "main.ts", in: package.appendingPathComponent("src"))
        let host = makeHost(packages: [package.path])
        let manifest = try await host.start()
        #expect(manifest.extensions == ["voz-pack"])
        #expect(await host.beforeInsert(text: "  padded  ", raw: "", app: app, timeout: .seconds(2)) == "padded")
        await host.stop()
    }
}
