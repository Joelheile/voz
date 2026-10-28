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
        try await Task.sleep(for: .milliseconds(500))
        for (suffix, name) in appearances {
            let appearance = NSAppearance(named: name)!
            for (title, status, hint) in popoverStates {
                try write(fixture.popover(status: status, hint: hint), to: outputDirectory, name: "popover-\(title)-\(suffix)", appearance: appearance)
            }
            for (title, page) in pages {
                try write(fixture.popover(page: page), to: outputDirectory, name: "popover-\(title)-\(suffix)", appearance: appearance)
            }
            try write(PermissionTileView(close: {}), to: outputDirectory, name: "permission-tile-\(suffix)", appearance: appearance)
            for (title, settled, latest) in previewTexts {
                let model = IndicatorModel()
                model.isExpanded = true
                model.preview = settled + latest
                try write(
                    IndicatorView(model: model, layout: previewLayout)
                        .environment(\.colorScheme, name == .darkAqua ? .dark : .light),
                    to: outputDirectory,
                    name: "live-preview-\(title)-\(suffix)",
                    appearance: appearance
                )
            }
            for step in SetupStep.allCases {
                fixture.sources.setup.step = step
                try write(fixture.popover(needsSetup: true), to: outputDirectory, name: "popover-setup-\(step)-\(suffix)", appearance: appearance)
            }
        }
    }

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

    private static let previewLayout = IndicatorLayout.make(visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 888))

    private static let pages: [(String, PopoverPage)] = [
        ("settings", .settings),
        ("dictionary", .dictionary),
        ("insights", .insights),
        ("extensions", .extensions),
        ("cleanup-prompt", .cleanupPrompt),
        ("cleanup-steps", .cleanupSteps),
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
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
        for word in ["Voz", "FluidAudio"] { try history.vocabulary.suggest(word) }
        sources = PopoverSources(
            settings: settings,
            modelStatus: status,
            history: HistoryModel(store: history),
            stats: StatsModel(store: history),
            vocabulary: VocabularyModel(store: history.vocabulary, analytics: analytics),
            setup: SetupModel(analytics: analytics) {},
            extensions: ExtensionsModel(analytics: analytics, home: home, cache: nil, fetch: { _ in Self.listings }),
            catalog: ExtensionCatalog()
        )
        status.update(.parakeetUltra, .ready(bytes: 483_000_000))
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

    nonisolated private static let listings = Data("""
    {"objects": [
      {"downloads": {"monthly": 5310}, "package": {"name": "voz-tone", "description": "Rewrites your dictation in the tone of each app", "version": "1.4.0", "publisher": {"username": "mara"}}},
      {"downloads": {"monthly": 3720}, "package": {"name": "voz-snippets", "description": "Say a shortcut, get your address, signature or links", "version": "2.0.1", "publisher": {"username": "jonas"}}},
      {"downloads": {"monthly": 1840}, "package": {"name": "voz-obsidian", "description": "Appends each dictation to today's daily note", "version": "0.9.2", "publisher": {"username": "lee"}}},
      {"downloads": {"monthly": 410}, "package": {"name": "voz-linear", "description": "Say new ticket to file a Linear issue", "version": "0.3.0", "publisher": {"username": "sam"}}}
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
