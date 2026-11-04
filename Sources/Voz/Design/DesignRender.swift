import AppKit
import SwiftUI

@MainActor
enum DesignRender {
    private static let scale: CGFloat = 2
    private static let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    static func run(outputDirectory: URL) async throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let fixture = try Fixture()
        fixture.sources.stats.start()
        await fixture.sources.extensions.load()
        await fixture.sources.extensions.checkScreen("voz-tone")
        try await Task.sleep(for: .milliseconds(500))
        for (suffix, name) in appearances {
            let appearance = NSAppearance(named: name)!
            for (title, status, hint) in popoverStates {
                try write(fixture.popover(status: status, hint: hint), to: outputDirectory, name: "popover-\(title)-\(suffix)", appearance: appearance)
            }
            for (title, page) in pages {
                try write(fixture.popover(page: page), to: outputDirectory, name: "popover-\(title)-\(suffix)", appearance: appearance)
            }
            for (title, activity) in Fixture.meetingActivities {
                try write(fixture.popover(activity: activity), to: outputDirectory, name: "popover-meeting-\(title)-\(suffix)", appearance: appearance)
            }
            fixture.sources.extensions.selected = "voz-tone"
            try write(fixture.popover(page: .extensions), to: outputDirectory, name: "popover-extension-detail-\(suffix)", appearance: appearance)
            fixture.sources.extensions.selected = nil
            fixture.sources.vocabulary.draft = "Kowalski"
            try write(fixture.popover(page: .dictionary), to: outputDirectory, name: "popover-dictionary-adding-\(suffix)", appearance: appearance)
            fixture.sources.vocabulary.draft = ""
            try write(PermissionTileView(close: {}), to: outputDirectory, name: "permission-tile-\(suffix)", appearance: appearance)
            for (title, settled, latest) in previewTexts {
                for (style, hasNotch) in [("notch", true), ("floating", false)] {
                    let model = IndicatorModel()
                    model.isExpanded = true
                    model.preview = settled + latest
                    try write(
                        IndicatorView(model: model, layout: previewLayout(hasNotch: hasNotch))
                            .environment(\.colorScheme, hasNotch || name == .darkAqua ? .dark : .light),
                        to: outputDirectory,
                        name: "live-preview-\(style)-\(title)-\(suffix)",
                        appearance: appearance
                    )
                }
            }
            for (title, state, targeted) in indicatorStates {
                for (style, hasNotch) in [("notch", true), ("floating", false)] {
                    let model = IndicatorModel()
                    model.isExpanded = true
                    model.state = state
                    model.isDropTargeted = targeted
                    try write(
                        IndicatorView(model: model, layout: previewLayout(hasNotch: hasNotch))
                            .environment(\.colorScheme, hasNotch || name == .darkAqua ? .dark : .light),
                        to: outputDirectory,
                        name: "indicator-\(style)-\(title)-\(suffix)",
                        appearance: appearance
                    )
                }
            }
            let invited = IndicatorModel()
            invited.state = .dropTarget
            invited.isInvitingDrop = true
            try write(
                IndicatorView(model: invited, layout: previewLayout(hasNotch: true)).environment(\.colorScheme, .dark),
                to: outputDirectory,
                name: "indicator-notch-drop-invite-\(suffix)",
                appearance: appearance
            )
            for (title, progress, hovering) in fileProgressStates {
                for (style, hasNotch) in [("notch", true), ("floating", false)] {
                    let model = IndicatorModel()
                    model.isExpanded = true
                    model.state = .transcribing
                    model.canCancel = true
                    model.progress = progress
                    model.isHovering = hovering
                    try write(
                        IndicatorView(model: model, layout: previewLayout(hasNotch: hasNotch))
                            .environment(\.colorScheme, hasNotch || name == .darkAqua ? .dark : .light),
                        to: outputDirectory,
                        name: "indicator-\(style)-\(title)-\(suffix)",
                        appearance: appearance
                    )
                }
            }
            for (title, text) in [("empty", ""), ("written", "# Weekly sync\nAsk Luca about the **API bump**\n## Decisions\n- Notes open from the notch\n  - Summary lands in `~/Meetings`\n    - One file per meeting\n1. Review the draft\n- [x] Pick a backup folder\n- [ ] Ship on Friday")] {
                for expanded in [false, true] {
                    let note = NoteModel()
                    note.title = "Weekly sync"
                    note.text = text
                    note.focused = expanded
                    try write(
                        NoteView(model: note, onEdit: {}, onClose: {})
                            .frame(width: NoteController.width, height: expanded ? NoteController.expandedHeight : NoteController.compactHeight),
                        to: outputDirectory,
                        name: "note-\(title)-\(expanded ? "open" : "compact")-\(suffix)",
                        appearance: appearance
                    )
                }
            }
            for (title, stalled) in [("live", false), ("stalled", true)] {
                let live = LiveStatus()
                live.begin()
                live.hear("Speaker 1: so the plan is to ship on Friday. You: Milan, can you own the changelog? Speaker 1: yes, I'll write it tonight and send it over")
                live.stalled = stalled
                for expanded in [false, true] {
                    let note = NoteModel()
                    note.title = "Notes"
                    note.text = "# Release\n- Ship Friday\n- Milan owns the changelog\n- [ ] Send the draft tonight"
                    note.live = live
                    note.focused = expanded
                    try write(
                        NoteView(model: note, onEdit: {}, onClose: {})
                            .frame(width: NoteController.width, height: expanded ? NoteController.expandedHeight : NoteController.compactHeight),
                        to: outputDirectory,
                        name: "note-meeting-\(title)-\(expanded ? "open" : "compact")-\(suffix)",
                        appearance: appearance
                    )
                }
                let model = IndicatorModel()
                model.isExpanded = true
                model.state = .activity
                model.live = live
                model.canStop = true
                model.recordingStart = Date().addingTimeInterval(-754)
                for (index, level) in [0.2, 0.6, 0.4, 0.8, 0.3, 0.7, 0.5].enumerated() {
                    model.levels.append(Float(level), at: Date.now.timeIntervalSinceReferenceDate - Double(7 - index) * 0.08)
                }
                for (style, hasNotch) in [("notch", true), ("floating", false)] {
                    try write(
                        IndicatorView(model: model, layout: previewLayout(hasNotch: hasNotch))
                            .environment(\.colorScheme, hasNotch || name == .darkAqua ? .dark : .light),
                        to: outputDirectory,
                        name: "indicator-\(style)-meeting-\(title)-\(suffix)",
                        appearance: appearance
                    )
                }
            }
            let ask = AskModel()
            ask.load(Self.calendarAsk)
            let edit = AskModel()
            edit.load(Self.editAsk)
            try write(AskView(model: edit, onAnswer: { _ in }, onClose: {}), to: outputDirectory, name: "ask-edit-\(suffix)", appearance: appearance)
            let pick = AskModel()
            pick.load(AIModels.pickCard)
            try write(AskView(model: pick, onAnswer: { _ in }, onClose: {}), to: outputDirectory, name: "ask-model-\(suffix)", appearance: appearance)
            try write(AskView(model: ask, onAnswer: { _ in }, onClose: {}), to: outputDirectory, name: "ask-calendar-\(suffix)", appearance: appearance)
            ask.load(Self.meetingAsk)
            try write(AskView(model: ask, onAnswer: { _ in }, onClose: {}), to: outputDirectory, name: "ask-meeting-\(suffix)", appearance: appearance)
            for step in SetupStep.allCases {
                fixture.sources.setup.step = step
                try write(fixture.popover(needsSetup: true), to: outputDirectory, name: "popover-setup-\(step)-\(suffix)", appearance: appearance)
            }
        }
    }

    private static let meetingAsk = AskParams(
        call: 0, deadline: 0, title: "Zoom call started", message: "Record it and take notes?", icon: "audio-lines",
        fields: [], buttons: ["Not now", "Record"], remaining: 0
    )

    private static let calendarAsk = AskParams(
        call: 0,
        deadline: 0,
        title: "Add to calendar?",
        fields: [
            AskField(id: "title", label: "Title", type: .text, value: .string("Moritz Entlassung"), options: nil),
            AskField(id: "start", label: "Starts", type: .date, value: .number(1_796_515_200_000), options: nil),
            AskField(id: "end", label: "Ends", type: .date, value: .number(1_796_518_800_000), options: nil),
            AskField(id: "location", label: "Location", type: .text, value: .string("Fritzlar"), options: nil),
            AskField(id: "calendar", label: "Calendar", type: .choice, value: .string("Home"), options: ["Home", "Work", "Family"]),
        ],
        buttons: ["Copy", "Add"],
        remaining: 0
    )

    private static let editAsk = AskParams(
        call: 0,
        deadline: 0,
        title: "How should it change?",
        fields: [AskField(id: "instruction", label: "Leave empty to fix mistakes", type: .text, value: .string(""), options: nil)],
        buttons: ["Shorter", "Clearer", "Edit"],
        remaining: 0
    )

    private static let popoverStates: [(String, PopoverStatus, String)] = [
        ("ready", .ready, ""),
        ("recording", .recording, ""),
        ("transcribing", .transcribing, "Processing your recording"),
        ("loading", .loadingModel(detail: "42%, 3 min left", progress: 0.42), "42%, 3 min left"),
        ("permission", .permissionNeeded(.accessibility), PermissionFix.accessibility.detail),
        ("failed", .modelFailed("Download failed. Check your connection"), "Download failed. Check your connection"),
    ]

    private static let previewTexts = [
        ("short", "", "Let's move the review to Thursday afternoon."),
        ("long", String(repeating: "Keep the latest words visible as the recording gets longer. ", count: 6), "These are the words you just said."),
        ("multilingual", "Morgen besprechen wir Voz und die nächsten Schritte. ", "然后继续讨论我们的计划。"),
    ]

    private static let indicatorStates: [(String, IndicatorState, Bool)] = [
        ("done", .done, false),
        ("failed", .failed, false),
        ("drop", .dropTarget, false),
        ("drop-targeted", .dropTarget, true),
        ("activity", .activity, false),
    ]

    private static let fileProgressStates: [(String, Double?, Bool)] = [
        ("file-starting", nil, false),
        ("file-progress", 0.42, false),
        ("file-cancel", 0.42, true),
    ]

    private static func previewLayout(hasNotch: Bool) -> IndicatorLayout {
        IndicatorLayout.make(screen: ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: hasNotch ? 32 : 0,
            leftAreaWidth: hasNotch ? 662 : nil,
            rightAreaWidth: hasNotch ? 662 : nil,
            visibleMinY: 0
        ))
    }

    private static let pages: [(String, PopoverPage)] = [
        ("settings", .settings),
        ("dictionary", .dictionary),
        ("insights", .insights),
        ("extensions", .extensions),
        ("feedback", .feedback),
        ("cleanup", .cleanup),
        ("privacy", .privacy),
        ("cleanup-prompt", .cleanupPrompt),
        ("cleanup-steps", .cleanupSteps),
        ("languages", .languages),
        ("ai-model", .aiModel),
        ("whats-new", .whatsNew),
        ("tour", .tour),
    ]

    private static func write(_ view: some View, to directory: URL, name: String, appearance: NSAppearance) throws {
        let host = NSHostingView(rootView: view.padding(28).background(Theme.canvas).transaction { $0.disablesAnimations = true })
        host.appearance = appearance
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let resolved = host.fittingSize
        host.frame = NSRect(origin: .zero, size: resolved)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(resolved.width * scale),
            pixelsHigh: Int(resolved.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        rep.size = resolved
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        print(url.path)
    }
}

@MainActor
private final class Fixture {
    let settings: AppSettings
    let status = ModelStatus()
    let history: HistoryStore
    let sources: PopoverSources
    let analytics = Analytics(usage: false, errors: false, installID: UUID())
    let records: [TranscriptRecord]

    init() throws {
        let suite = "com.joelheile.voz.render"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let home = VozHome(root: FileManager.default.temporaryDirectory.appendingPathComponent("voz-render-home"))
        settings = AppSettings(defaults: UserDefaults(suiteName: suite)!, home: home)
        history = try HistoryStore()
        records = Self.makeRecords()
        for record in records { try history.insert(record) }
        for word in ["Joel", "Parakeet", "GRDB", "Sparkle", "Wispr Flow", "Heil-Escobar"] { try history.vocabulary.add(word, source: .manual) }
        try history.vocabulary.add("superbass -> Supabase", source: .manual)
        for (word, heard) in [("Voz", "voss"), ("FluidAudio", "fluid audio")] { try history.vocabulary.suggest(word, aliases: [heard]) }
        sources = PopoverSources(
            settings: settings,
            modelStatus: status,
            history: HistoryModel(store: history),
            stats: StatsModel(store: history),
            vocabulary: VocabularyModel(store: history.vocabulary, analytics: analytics),
            setup: SetupModel(analytics: analytics) {},
            extensions: ExtensionsModel(analytics: analytics, home: home, cache: nil, fetch: { url in url.lastPathComponent == "latest" ? Self.screenReader : Self.listings }),
            catalog: ExtensionCatalog(actions: [Self.meetingAction]),
            updater: Updater(settings: settings, isBusy: { false })
        )
        status.update(.parakeetUltra, .ready(bytes: 483_000_000))
    }

    nonisolated static let meetingAction = ExtensionAction(
        id: "voz-meeting/meeting", name: "Record meeting", hotkey: "ctrl+opt+m", hidden: false, icon: "audio-lines", extension: "voz-meeting"
    )
    nonisolated static let meetingActivities = [
        ("recording", ExtensionActivity(id: "1", title: "Recording meeting", since: Date().addingTimeInterval(-754), stoppable: true, openable: true)),
        ("saving", ExtensionActivity(id: "2", title: "Saving meeting", since: Date().addingTimeInterval(-8), stoppable: false, openable: false)),
    ]

    func popover(activity: ExtensionActivity) -> some View {
        let action = Self.meetingAction
        let hidden = ExtensionAction(id: action.id, name: action.name, hotkey: action.hotkey, hidden: true, icon: action.icon, extension: action.extension)
        let sources = PopoverSources(
            settings: settings, modelStatus: status, history: self.sources.history, stats: self.sources.stats,
            vocabulary: self.sources.vocabulary, setup: self.sources.setup, extensions: self.sources.extensions,
            catalog: ExtensionCatalog(actions: [hidden], activities: [activity]), updater: self.sources.updater
        )
        let model = PopoverModel()
        model.hint = Self.hint(for: .ready, settings: settings)
        return PopoverView(model: model, sources: sources)
    }

    func popover(status: PopoverStatus = .ready, hint: String = "", page: PopoverPage = .home, needsSetup: Bool = false) -> some View {
        let model = PopoverModel()
        model.status = status
        model.hint = hint.isEmpty ? Self.hint(for: status, settings: settings) : hint
        model.page = page
        model.needsSetup = needsSetup
        return PopoverView(model: model, sources: sources)
    }

    private static func hint(for status: PopoverStatus, settings: AppSettings) -> String {
        switch status {
        case .recording: DictationHint.recording(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
        default: DictationHint.idle(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
        }
    }

    nonisolated private static let screenReader = Data(#"{"voz": {"screen": true}}"#.utf8)
    nonisolated private static let listings = Data("""
    {"objects": [
      {"downloads": {"monthly": 5310}, "package": {"date": "2026-10-30T09:12:00.000Z", "links": {"npm": "https://www.npmjs.com/package/voz-tone"}, "name": "voz-tone", "description": "Rewrites your dictation in the tone of each app", "version": "1.4.0", "publisher": {"username": "mara"}}},
      {"downloads": {"monthly": 3720}, "package": {"date": "2026-10-12T09:12:00.000Z", "links": {"npm": "https://www.npmjs.com/package/voz-snippets"}, "name": "voz-snippets", "description": "Say a shortcut, get your address, signature or links", "version": "2.0.1", "publisher": {"username": "jonas"}}},
      {"downloads": {"monthly": 1840}, "package": {"date": "2026-08-02T09:12:00.000Z", "links": {"npm": "https://www.npmjs.com/package/voz-obsidian"}, "name": "voz-obsidian", "description": "Appends each dictation to today's daily note", "version": "0.9.2", "publisher": {"username": "lee"}}},
      {"downloads": {"monthly": 410}, "package": {"date": "2026-06-20T09:12:00.000Z", "links": {"npm": "https://www.npmjs.com/package/voz-linear"}, "name": "voz-linear", "description": "Say new ticket to file a Linear issue", "version": "0.3.0", "publisher": {"username": "sam"}}}
    ]}
    """.utf8)

    private static func makeRecords() -> [TranscriptRecord] {
        let texts = [
            "Let's move the review to Thursday afternoon, and I'll send the agenda tonight.",
            "Remind me to send the invoice before the end of the month.",
            "The build is green again after the dependency bump.",
            "I think we should ship the beta on Friday and watch the crash reports over the weekend.",
            "Can you check whether the new hotkey capture still works with the right option key?",
            "Thanks for the quick turnaround. I'll take another look tomorrow morning.",
        ]
        let apps = [
            ("Messages", "com.apple.MobileSMS"),
            ("Slack", "com.tinyspeck.slackmacgap"),
            ("Mail", "com.apple.mail"),
            ("Notes", "com.apple.Notes"),
            ("Safari", "com.apple.Safari"),
        ]
        let now = Date()
        var result: [TranscriptRecord] = []
        let recent: [TimeInterval] = [120, 3_600, 3 * 3_600]
        for (index, seconds) in recent.enumerated() {
            result.append(record(text: texts[index], at: now.addingTimeInterval(-seconds), app: apps[index]))
        }
        result.insert(TranscriptRecord(ExtensionHistoryEntry(
            extension: "voz-meeting", text: "Release plan: ship Friday, Milan owns the changelog", seconds: 1_800, file: "/tmp/standup.md",
            copies: [HistoryCopy(name: "Notes", text: "ship fri"), HistoryCopy(name: "Transcript", text: "Speaker 1: Let's start with the release plan for Friday.")]
        )), at: 1)
        for day in 0..<30 where day % 5 != 3 {
            for entry in 0..<(1 + day % 3) {
                let text = texts[(day + entry) % texts.count]
                let date = now.addingTimeInterval(-Double(day) * 86_400 - Double(entry) * 5_400 - 14_400)
                result.append(record(text: text, at: date, app: apps[(day + entry) % apps.count]))
            }
        }
        return result
    }

    private static func record(text: String, at date: Date, app: (name: String, bundleID: String)) -> TranscriptRecord {
        TranscriptRecord(
            createdAt: date,
            rawText: text,
            audioSeconds: Double(text.split(separator: " ").count) / 2.6,
            sttMs: 180,
            totalMs: 420,
            model: SpeechModel.parakeetUltra.rawValue,
            appBundleID: app.bundleID,
            appName: app.name,
            fillerWordsRemoved: text.count % 4
        )
    }
}
