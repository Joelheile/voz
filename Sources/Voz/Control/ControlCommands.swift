import Foundation

/// Everything you can do in Voz from the terminal, an agent's shell or MCP
@MainActor
struct ControlCommands {
    let history: HistoryStore
    let settings: AppSettings
    let extensions: ExtensionsModel
    let catalog: ExtensionCatalog
    let dictation: DictationControl
    var home = VozHome()
    var telemetryStore = TelemetryStore.shared
    var telemetryDefaults = UserDefaults.standard

    /// What the CLI needs from a dictation, so tests can stand in for the microphone
    struct DictationControl {
        let phase: @MainActor () -> DictationPhase
        let handle: @MainActor (HotkeyAction) -> Void
        let stopWithoutInserting: @MainActor () -> Void
        var stopAndSend: @MainActor () -> Void = {}
        var cancel: @MainActor () -> Void = {}
    }

    /// How long `dictation stop --print` waits for the text: a long recording plus model cleanup
    static let printWait = Duration.seconds(90)

    func all() -> [ControlCommand] {
        [status] + LocalCommands.all(inTerminal: false) + [dictationCommand("start"), dictationCommand("stop"), dictationCommand("toggle"), dictationCancel, historyCommand, last, draftList,
         vocabularyList, vocabularyAdd, vocabularyRemove, extensionList, search, enable(true), enable(false), config, settingsCommand, aiCommand, modelList, feedback, telemetry, commandList]
            + catalog.tools.map(tool) + catalog.actions.filter { !$0.hidden }.map(action)
    }

    // MARK: Status and dictation

    private struct Status: Encodable {
        let version: String
        let pid: Int32
        let dictation: String
        let speechModel: String
        let microphone: Bool
        let accessibility: Bool
        let extensions: [String]
        let errors: [String: String]
    }

    private var status: ControlCommand {
        ControlCommand(name: "status", summary: "Show whether Voz can dictate: version, permissions, model and extensions", input: .object([]), readOnly: true) { _ in
            let status = Status(
                version: SystemContext.appVersion,
                pid: getpid(),
                dictation: "\(dictation.phase())",
                speechModel: settings.speechModel,
                microphone: Permissions.microphoneGranted,
                accessibility: Permissions.accessibilityGranted,
                extensions: catalog.loaded,
                errors: catalog.errors.merging(catalog.hostError.map { ["host": $0] } ?? [:]) { $1 }
            )
            let value = try JSONValue(encoding: status)
            return ControlOutput(value, text: value.human)
        }
    }

    private func dictationCommand(_ verb: String) -> ControlCommand {
        let summaries = ["start": "Start recording, like tapping the hotkey", "stop": "Stop recording and insert the text", "toggle": "Start or stop recording"]
        let input: [GenerationSpec.Property] = verb == "stop"
            ? [
                .init(name: "print", schema: .boolean("Print the text here instead of inserting it, once Voz has transcribed it"), optional: true),
                .init(name: "send", schema: .boolean("Press Return after inserting the text, so a chat message goes out"), optional: true),
            ]
            : []
        return ControlCommand(name: "dictation/\(verb)", summary: summaries[verb]!, input: .object(input)) { arguments in
            let before = dictation.phase()
            if before == .transcribing { throw ControlError.failed("Voz is still transcribing. Try again in a moment.") }
            let prints = arguments["print"] == .bool(true), sends = arguments["send"] == .bool(true)
            if prints, sends { throw ControlError.usage("Use --print or --send, not both.") }
            if prints { return try await stopAndPrint(recording: before == .recording) }
            if sends {
                guard before == .recording else { return .message("Not recording.", changed: false) }
                dictation.stopAndSend()
                return .message("Stopped. Voz inserts the text and presses Return when it's ready.")
            }
            let starts = verb == "start" || (verb == "toggle" && before == .idle)
            if starts == (before == .recording) { return .message(starts ? "Already recording." : "Not recording.", changed: false) }
            dictation.handle(.toggle)
            if starts, dictation.phase() != .recording {
                throw ControlError.failed("Voz could not start recording. Run voz status to check microphone access.")
            }
            return .message(starts ? "Recording. Run voz dictation stop to finish." : "Stopped. Voz inserts the text when it's ready.")
        }
    }

    private var dictationCancel: ControlCommand {
        ControlCommand(name: "dictation/cancel", summary: "Stop recording and throw the audio away, like Esc", input: .object([])) { _ in
            guard dictation.phase() == .recording else { return .message("Not recording.", changed: false) }
            dictation.cancel()
            return .message("Canceled. Voz kept nothing.")
        }
    }

    private func stopAndPrint(recording: Bool) async throws -> ControlOutput {
        guard recording else { throw ControlError.failed("Not recording, so there is nothing to print. Run voz dictation start first.") }
        let stopped = Date()
        dictation.stopWithoutInserting()
        let deadline = ContinuousClock.now + Self.printWait
        while dictation.phase() != .idle {
            guard ContinuousClock.now < deadline else { throw ControlError.failed("Voz is still transcribing. Read the text later with voz last.") }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let record = try history.recent(limit: 5).first(where: { $0.createdAt >= stopped && $0.source == nil }), !record.finalText.isEmpty else {
            throw ControlError(code: .noSpeech, error: "Voz heard no speech. Check the microphone with voz status.")
        }
        return try ControlOutput(Dictation(record), text: record.finalText)
    }

    // MARK: History

    private struct Dictation: Encodable {
        let date: Date
        let app: String?
        let text: String
        let file: String?

        init(_ record: TranscriptRecord) {
            date = record.createdAt
            app = record.appName
            text = record.finalText
            file = record.file
        }
    }

    private var historyCommand: ControlCommand {
        ControlCommand(
            name: "history",
            summary: "List what you dictated, newest first",
            input: .object([
                .init(name: "query", schema: .string("Words in the text, such as \"invoice\""), optional: true),
                .init(name: "app", schema: .string("App name, such as \"Slack\""), optional: true),
                .init(name: "since", schema: .string("Only dictations on or after this date, as YYYY-MM-DD"), optional: true),
                .init(name: "limit", schema: .integer("How many to return, 20 unless you say"), optional: true),
            ]),
            positionals: ["query"],
            readOnly: true
        ) { arguments in
            let since = try arguments["since"]?.string.map(Self.day)
            let limit = arguments["limit"].flatMap { if case .number(let n) = $0 { Int(n) } else { nil } } ?? 20
            let records = try history.recent(matching: arguments["query"]?.string ?? "", app: arguments["app"]?.string, since: since, limit: max(1, limit))
            let text = records.isEmpty ? "No dictations match. Try fewer words or drop a filter." : records.map(Self.line).joined(separator: "\n")
            return try ControlOutput(records.map(Dictation.init), text: text)
        }
    }

    private var last: ControlCommand {
        ControlCommand(name: "last", summary: "Print your last dictation", input: .object([]), readOnly: true) { _ in
            guard let record = try history.recent(limit: 1).first else { throw ControlError.notFound("You have no dictations yet.") }
            return try ControlOutput(Dictation(record), text: record.finalText)
        }
    }

    // MARK: Drafts

    private struct Draft: Encodable {
        let date: Date
        let source: String
        let app: String?
        let thread: String?
        let instruction: String?
        let input: String
        let output: String
        let result: String?
        let outcome: DraftOutcome
    }

    private var draftList: ControlCommand {
        ControlCommand(
            name: "drafts",
            summary: "List text extensions inserted, and whether you kept, edited, sent or removed it",
            input: .object([
                .init(name: "source", schema: .string("Extension name, such as \"reply\""), optional: true),
                .init(name: "limit", schema: .integer("How many to return, 20 unless you say"), optional: true),
            ]),
            positionals: ["source"],
            readOnly: true
        ) { arguments in
            let sources = arguments["source"]?.string.map { name in name.hasPrefix("voz-") ? [name, String(name.dropFirst(4))] : [name, "voz-\(name)"] }
            let limit = arguments["limit"].flatMap { if case .number(let n) = $0 { Int(n) } else { nil } } ?? 20
            let rows = try history.drafts.recent(sources: sources, limit: max(1, limit))
            let drafts = rows.map { row in
                Draft(date: row.draft.createdAt, source: row.draft.source, app: row.thread?.app, thread: row.thread?.title, instruction: row.draft.instruction,
                      input: row.draft.input, output: row.draft.output, result: row.draft.result, outcome: row.draft.outcome)
            }
            let text = drafts.isEmpty ? "No drafts yet. Extensions such as reply save one each time they insert text." : drafts.map(Self.line).joined(separator: "\n")
            return try ControlOutput(drafts, text: text)
        }
    }

    private static func line(_ draft: Draft) -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HH:mm"
        let text = (draft.result ?? draft.output).replacingOccurrences(of: "\n", with: " ")
        return [format.string(from: draft.date), draft.source, draft.thread ?? "No thread", draft.outcome.rawValue, text].joined(separator: "  ")
    }

    // MARK: Vocabulary

    private struct Term: Encodable {
        let word: String
        let aliases: [String]
    }

    private var vocabularyList: ControlCommand {
        ControlCommand(name: "vocabulary/list", summary: "List the words Voz listens for", input: .object([]), readOnly: true) { _ in
            let terms = try history.vocabulary.terms().map { Term(word: $0.word, aliases: $0.aliases) }
            let text = terms.isEmpty ? "No words yet. Add one with voz vocabulary add <word>." : terms.map { ([$0.word] + $0.aliases).joined(separator: "  ") }.joined(separator: "\n")
            return try ControlOutput(terms, text: text)
        }
    }

    private var vocabularyAdd: ControlCommand {
        ControlCommand(
            name: "vocabulary/add",
            summary: "Teach Voz a word, such as a name it gets wrong",
            input: .object([.init(name: "word", schema: .string("The word, or \"heard -> word\" to replace what Voz hears"), optional: false)]),
            positionals: ["word"]
        ) { arguments in
            let entry = arguments["word"]?.string ?? ""
            let (heard, word) = VocabularyRule.parse(entry)
            guard !word.isEmpty else { throw ControlError.usage("Give a word, such as voz vocabulary add Kubernetes") }
            if heard == nil, try history.vocabulary.contains(word) { return .message("\(word) is already in your vocabulary.", changed: false) }
            try history.vocabulary.add(entry, source: .manual)
            return .message(heard.map { "Voz now writes \(word) when it hears \($0)." } ?? "Added \(word).")
        }
    }

    private var vocabularyRemove: ControlCommand {
        ControlCommand(
            name: "vocabulary/remove",
            summary: "Remove a word from your vocabulary",
            input: .object([.init(name: "word", schema: .string("The word to remove"), optional: false)]),
            positionals: ["word"]
        ) { arguments in
            let word = arguments["word"]?.string ?? ""
            guard try history.vocabulary.remove(word: word) else { return .message("\(word) is not in your vocabulary.", changed: false) }
            return .message("Removed \(word).")
        }
    }

    // MARK: AI model

    private struct AIStatus: Encodable {
        let model: String
        let account: String?
    }

    private var aiCommand: ControlCommand {
        ControlCommand(
            name: "ai",
            summary: "Show or pick the model extensions write with: apple on your Mac, your ChatGPT plan, or a Claude API key",
            input: .object([
                .init(name: "model", schema: .string("apple, chatgpt to sign in with your browser, or claude", choices: AIProvider.allCases.map(\.rawValue)), optional: true),
                .init(name: "key", schema: .string("Claude API key. Pass - to read it from stdin"), optional: true),
            ]),
            positionals: ["model", "key"]
        ) { arguments in
            guard let raw = arguments["model"]?.string else {
                let account = settings.aiAccount.isEmpty ? nil : settings.aiAccount
                let status = AIStatus(model: settings.aiModel.rawValue, account: account)
                return try ControlOutput(status, text: [settings.aiModel.name, account].compactMap(\.self).joined(separator: "  "))
            }
            guard let model = AIProvider(rawValue: raw) else {
                throw ControlError.usage("Pick apple, chatgpt or claude, not \"\(raw)\".\(ControlArguments.suggestion(for: raw, in: AIProvider.allCases.map(\.rawValue)))")
            }
            do {
                switch model {
                case .apple:
                    if settings.aiModel == .apple { return .message("Extensions already use Apple's model.", changed: false) }
                    let revoked = await AIModels.useApple(settings)
                    return .message(revoked ? "Extensions now use Apple's model on your Mac." : "Extensions now use Apple's model. OpenAI didn't confirm the sign-out, so remove Voz under Connected apps in ChatGPT settings.")
                case .chatgpt:
                    let email = try await AIModels.signInToChatGPT(settings)
                    return .message("Signed in to ChatGPT as \(email). Extensions now use your plan.")
                case .claude:
                    guard let key = arguments["key"]?.string else {
                        throw ControlError.usage("Add your key, such as pbpaste | voz ai claude -. Create one at platform.claude.com/settings/keys")
                    }
                    try await AIModels.useClaude(key: key, settings)
                    return .message("Extensions now use Claude with your API key.")
                }
            } catch let error as CloudModelError {
                throw ControlError.failed(error.localizedDescription)
            }
        }
    }

    private var modelList: ControlCommand {
        ControlCommand(name: "models", summary: "List the models extensions can ask for, and which one each tier runs", input: .object([]), readOnly: true) { _ in
            let list: AIModelList
            do {
                list = try await ModelLists.shared.list(for: settings.aiModel)
            } catch let error as CloudModelError {
                throw ControlError.failed(error.localizedDescription)
            }
            let tierOf = Dictionary(list.tiers.map { ($1, $0) }) { first, _ in first }
            let lines = list.models.map { model in
                [tierOf[model.id] ?? "", model.id, model.name].joined(separator: "  ").trimmingCharacters(in: .whitespaces)
            }
            return try ControlOutput(list, text: lines.joined(separator: "\n"))
        }
    }

    // MARK: Feedback

    private var feedback: ControlCommand {
        ControlCommand(
            name: "feedback",
            summary: "Tell the Voz developer what works, what breaks or what's missing",
            input: .object([
                .init(name: "message", schema: .string("What you want to say"), optional: false),
                .init(name: "email", schema: .string("Where to reply, if you want an answer"), optional: true),
            ]),
            positionals: ["message"]
        ) { arguments in
            let feedback = Feedback(message: arguments["message"]?.string ?? "", email: arguments["email"]?.string ?? "", speechModel: settings.speechModel)
            guard !feedback.isEmpty else { throw ControlError.usage("Give a message, such as voz feedback \"Short words get cut off\"") }
            do {
                try await feedback.send()
            } catch {
                throw ControlError.failed("Voz could not send your feedback: \(error.localizedDescription)")
            }
            return .message("Sent. Thanks for the feedback.")
        }
    }

    private var telemetry: ControlCommand {
        ControlCommand(name: "telemetry", summary: "Show exactly what Voz sends and what it holds on this Mac", input: .object([]), readOnly: true) { _ in
            let report = TelemetryReport(
                usageEnabled: settings.analyticsEnabled,
                errorsEnabled: settings.errorReportsEnabled,
                held: telemetryStore.held(),
                queued: TelemetrySender.queuedEvents(in: telemetryDefaults)
            )
            return try ControlOutput(report, text: report.text)
        }
    }

    private static func day(_ text: String) throws -> Date {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        format.locale = Locale(identifier: "en_US_POSIX")
        guard let date = format.date(from: text) else { throw ControlError.usage("--since must be a date like 2026-10-29, not \"\(text)\"") }
        return date
    }

    private static func line(_ record: TranscriptRecord) -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return [format.string(from: record.createdAt), record.appName ?? "Unknown app", record.finalText.replacingOccurrences(of: "\n", with: " ")].joined(separator: "  ")
    }

    // MARK: Extensions

    private struct ExtensionItem: Encodable {
        let name: String
        let version: String?
        let description: String?
        let enabled: Bool
        let loaded: Bool
        let error: String?
        /// Its package.json asks to read the text of the window in front
        let readsScreen: Bool
        let commands: [String]
        let settings: [SettingItem]
    }

    private struct SettingItem: Encodable {
        let key: String
        let title: String
        let type: String
        let value: JSONValue
        let options: [String]?
    }

    private var extensionList: ControlCommand {
        ControlCommand(name: "extensions", summary: "List installed extensions, their commands and settings", input: .object([]), readOnly: true) { _ in
            let disabled = try home.disabledExtensions()
            let items = try home.installedExtensions().map { item in
                ExtensionItem(
                    name: item.name,
                    version: item.version,
                    description: item.description,
                    enabled: !disabled.contains(item.name),
                    loaded: catalog.isLoaded(item.name),
                    error: catalog.error(for: item.name),
                    readsScreen: catalog.readsScreen(item.name),
                    commands: catalog.tools(for: item.name).map(\.id) + catalog.actions(for: item.name).map(\.id),
                    settings: settingItems(for: item.name)
                )
            }
            let text = items.isEmpty
                ? "No extensions installed. Find one with voz search."
                : items.map { [$0.name, $0.version ?? "", $0.enabled ? "on" : "off", $0.readsScreen ? "reads screen" : "", $0.error ?? $0.description ?? ""].filter { !$0.isEmpty }.joined(separator: "  ") }.joined(separator: "\n")
            return try ControlOutput(items, text: text)
        }
    }

    private struct Listing: Encodable {
        let name: String
        let version: String
        let summary: String?
        let installed: Bool
    }

    private var search: ControlCommand {
        ControlCommand(
            name: "search",
            summary: "Find extensions to install, from npm",
            input: .object([.init(name: "words", schema: .string("Words in the name or description, such as \"jira\""), optional: true)]),
            positionals: ["words"],
            readOnly: true
        ) { arguments in
            await extensions.load()
            if extensions.listings.isEmpty, let message = extensions.message { throw ControlError.failed(message) }
            let words = arguments["words"]?.string?.lowercased() ?? ""
            let installed = Set(try home.installedExtensions().map(\.name))
            let found = extensions.listings
                .filter { words.isEmpty || $0.name.lowercased().contains(words) || ($0.summary ?? "").lowercased().contains(words) }
                .map { Listing(name: $0.name, version: $0.version, summary: $0.summary, installed: installed.contains($0.name)) }
            let text = found.isEmpty
                ? "No extensions match. Try other words, or build one: run voz help."
                : found.map { [$0.name, $0.installed ? "installed" : "", $0.summary ?? ""].filter { !$0.isEmpty }.joined(separator: "  ") }.joined(separator: "\n")
            return try ControlOutput(found, text: text + (found.isEmpty ? "" : "\n\nInstall one with voz install <name>."))
        }
    }

    private func enable(_ enabled: Bool) -> ControlCommand {
        ControlCommand(
            name: enabled ? "enable" : "disable",
            summary: enabled ? "Turn an installed extension on" : "Turn an extension off without removing it",
            input: .object([.init(name: "extension", schema: .string("Extension or package name, such as voz-jira"), optional: false)]),
            positionals: ["extension"]
        ) { arguments in
            let name = try installedName(arguments["extension"]?.string ?? "")
            if try home.disabledExtensions().contains(name) != enabled { return .message("\(name) is already \(enabled ? "on" : "off").", changed: false) }
            extensions.setEnabled(name, enabled)
            if let message = extensions.message { throw ControlError.failed(message) }
            return .message("Turned \(name) \(enabled ? "on" : "off").")
        }
    }

    private var config: ControlCommand {
        ControlCommand(
            name: "config",
            summary: "Show or change an extension's settings",
            input: .object([
                .init(name: "extension", schema: .string("Extension name, such as voz-jira"), optional: false),
                .init(name: "key", schema: .string("Setting key. Leave out to list them all"), optional: true),
                .init(name: "value", schema: .string("New value. Pass - to read it from stdin, for tokens"), optional: true),
            ]),
            positionals: ["extension", "key", "value"]
        ) { arguments in
            let name = try installedName(arguments["extension"]?.string ?? "")
            let fields = catalog.settings(for: name).flatMap(\.fields)
            guard !fields.isEmpty else {
                throw ControlError.notFound(catalog.isLoaded(name) ? "\(name) has no settings." : "\(name) is not loaded, so Voz can't read its settings. Run voz enable \(name).")
            }
            guard let key = arguments["key"]?.string else {
                let items = settingItems(for: name)
                return try ControlOutput(items, text: items.map { "\($0.key)  \(Self.shown($0.value))  \($0.title)" }.joined(separator: "\n"))
            }
            guard let field = fields.first(where: { $0.key == key }) else {
                throw ControlError.usage("\(name) has no setting \(key).\(ControlArguments.suggestion(for: key, in: fields.map(\.key))) Run voz config \(name) to list them.")
            }
            guard let raw = arguments["value"]?.string else {
                let item = settingItem(field, name: name)
                return try ControlOutput(item, text: Self.shown(item.value))
            }
            let value = try Self.value(raw, for: field)
            if Self.json(value) == settingItem(field, name: name).value { return .message("\(key) is already \(Self.shown(Self.json(value))) for \(name).", changed: false) }
            extensions.setConfig(value, key: key, for: name)
            if let message = extensions.message { throw ControlError.failed(message) }
            return .message("Set \(key) for \(name).")
        }
    }

    private func installedName(_ name: String) throws -> String {
        let names = try home.installedExtensions().map(\.name)
        guard names.contains(name) else {
            throw ControlError.notFound("No installed extension is called \(name).\(ControlArguments.suggestion(for: name, in: names)) Run voz extensions to list them.")
        }
        return name
    }

    private func settingItems(for name: String) -> [SettingItem] {
        catalog.settings(for: name).flatMap(\.fields).map { settingItem($0, name: name) }
    }

    private func settingItem(_ field: SettingField, name: String) -> SettingItem {
        let value = field.value(in: extensions.config(for: name))
        let hidden = field.secret == true && value != .string("")
        return SettingItem(key: field.key, title: field.title, type: field.type.rawValue, value: hidden ? .string("(set)") : Self.json(value), options: field.options)
    }

    private static func json(_ value: SettingValue) -> JSONValue {
        switch value {
        case .string(let text): .string(text)
        case .number(let number): .number(number)
        case .boolean(let flag): .bool(flag)
        }
    }

    private static func shown(_ value: JSONValue) -> String {
        value == .string("") ? "(empty)" : value.text
    }

    private static func value(_ raw: String, for field: SettingField) throws -> SettingValue {
        switch field.type {
        case .string:
            if let options = field.options, !options.contains(raw) { throw ControlError.usage("\(field.key) must be one of \(options.joined(separator: ", ")), not \"\(raw)\"") }
            return .string(raw)
        case .number:
            guard let number = Double(raw) else { throw ControlError.usage("\(field.key) must be a number, not \"\(raw)\"") }
            return .number(number)
        case .boolean:
            guard ["true", "false"].contains(raw) else { throw ControlError.usage("\(field.key) must be true or false, not \"\(raw)\"") }
            return .boolean(raw == "true")
        }
    }

    private func tool(_ tool: ExtensionTool) -> ControlCommand {
        ControlCommand(name: tool.id, summary: tool.description, input: tool.input, positionals: tool.positional ?? [], readOnly: tool.readOnly, source: tool.extension) { arguments in
            let value = try await catalog.call(tool, input: arguments)
            return ControlOutput(value, text: value.human)
        }
    }

    private func action(_ action: ExtensionAction) -> ControlCommand {
        ControlCommand(name: action.id, summary: action.name, input: .object([]), source: action.extension) { _ in
            catalog.run(action)
            return .message("Started \(action.name).")
        }
    }

    // MARK: App settings

    private struct Setting {
        let key: String
        let summary: String
        let choices: [String]?
        let get: @MainActor () -> JSONValue
        let set: @MainActor (String) throws -> Void
    }

    private var appSettings: [Setting] {
        let flags: [(String, String, ReferenceWritableKeyPath<AppSettings, Bool>)] = [
            ("logText", "Write dictated text to the log, for debugging", \.logIncludesText),
            ("holdToTalk", "Hold the hotkey to talk, or tap it to start and stop", \.holdToTalk),
            ("muteWhileRecording", "Mute other apps while you dictate", \.muteWhileRecording),
            ("headphoneQuality", "Keep your mic when Bluetooth headphones connect, so they keep full sound quality", \.headphoneQuality),
            ("copyToClipboard", "Copy each dictation to the clipboard", \.copyToClipboard),
            ("insertIntoApp", "Type each dictation into the front app", \.insertIntoApp),
            ("quickSend", "Press Return while recording to insert the text and send it", \.quickSend),
            ("soundCues", "Play a sound when recording starts and stops", \.soundCues),
            ("livePreview", "Show words in the notch while you speak", \.livePreviewEnabled),
            ("launchAtLogin", "Open Voz when you log in", \.launchAtLogin),
            ("cleanup", "Clean up dictations with the model", \.cleanupEnabled),
            ("analytics", "Share per-dictation stats and site totals tied to a random ID", \.analyticsEnabled),
            ("betaUpdates", "Get beta updates", \.receiveBetaUpdates),
            ("autoUpdate", "Install updates while you're away from your Mac", \.installUpdatesAutomatically),
            ("errorReports", "Send crash and error reports", \.errorReportsEnabled),
        ]
        let texts: [(String, String, ReferenceWritableKeyPath<AppSettings, String>)] = [
            ("microphone", "Microphone name, empty for the system default", \.microphone),
            ("speechModel", "Speech model, such as parakeet-ultra", \.speechModel),
            ("cleanupModel", "Cleanup model, such as apple", \.cleanupModel),
            ("cleanupPrompt", "Extra instructions for the cleanup model", \.cleanupPrompt),
        ]
        return flags.map { key, summary, path in
            Setting(key: key, summary: summary, choices: ["true", "false"], get: { .bool(settings[keyPath: path]) }) { raw in
                let on = ControlArguments.trueWords.contains(raw.lowercased())
                guard on || ControlArguments.falseWords.contains(raw.lowercased()) else { throw ControlError.usage("\(key) must be on or off, not \"\(raw)\"") }
                settings[keyPath: path] = on
            }
        } + texts.map { key, summary, path in
            Setting(key: key, summary: summary, choices: nil, get: { .string(settings[keyPath: path]) }) { settings[keyPath: path] = $0 }
        } + [
            Setting(key: "cleanupMode", summary: "light keeps your words, heavy rewrites more", choices: CleanupMode.allCases.map(\.rawValue), get: { .string(settings.cleanupMode.rawValue) }) { raw in
                guard let mode = CleanupMode(rawValue: raw) else { throw ControlError.usage("cleanupMode must be light or heavy, not \"\(raw)\"") }
                settings.cleanupMode = mode
            },
            Setting(key: "cleanupSteps", summary: "Cleanup steps in order, separated by commas", choices: nil, get: { .array(settings.cleanupSteps.map(JSONValue.string)) }) { raw in
                settings.cleanupSteps = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            },
        ]
    }

    private var settingsCommand: ControlCommand {
        ControlCommand(
            name: "settings",
            summary: "Show or change Voz settings",
            input: .object([
                .init(name: "key", schema: .string("Setting key. Leave out to list them all"), optional: true),
                .init(name: "value", schema: .string("New value"), optional: true),
            ]),
            positionals: ["key", "value"]
        ) { arguments in
            let all = appSettings
            guard let key = arguments["key"]?.string else {
                let values = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0.get()) })
                return ControlOutput(.object(values), text: all.map { "\($0.key)  \(Self.shown($0.get()))  \($0.summary)" }.joined(separator: "\n"))
            }
            guard let setting = all.first(where: { $0.key == key }) else {
                throw ControlError.usage("No setting \(key).\(ControlArguments.suggestion(for: key, in: all.map(\.key))) Run voz settings to list them.")
            }
            guard let raw = arguments["value"]?.string else { return ControlOutput(setting.get(), text: Self.shown(setting.get())) }
            let before = setting.get()
            try setting.set(raw)
            if setting.get() == before { return .message("\(key) is already \(Self.shown(before)).", changed: false) }
            return .message("Set \(key) to \(Self.shown(setting.get())).")
        }
    }

    // MARK: Introspection

    private struct CommandItem: Encodable {
        let name: String
        let summary: String
        let usage: String
        let readOnly: Bool
        let source: String?
        let inputSchema: JSONValue
    }

    private var commandList: ControlCommand {
        ControlCommand(name: "commands", summary: "List every command with its input schema, for agents", input: .object([]), readOnly: true) { _ in
            let items = all().filter { !$0.terminalOnly }.map { CommandItem(name: $0.name, summary: $0.summary, usage: $0.usage, readOnly: $0.readOnly, source: $0.source, inputSchema: $0.input.jsonSchema) }
            return try ControlOutput(items, text: items.map(\.usage).joined(separator: "\n"))
        }
    }
}
