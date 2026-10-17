import AppKit
import SwiftUI
import VozCore

@MainActor
enum DesignRender {
    private static let scale: CGFloat = 2
    private static let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    static func run(outputDirectory: URL) async throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let fixture = try Fixture()
        try await Task.sleep(for: .milliseconds(500))
        for (suffix, name) in appearances {
            let appearance = NSAppearance(named: name)!
            for (title, status, hint) in popoverStates {
                let model = fixture.popoverModel(status: status, hint: hint)
                try write(PopoverView(model: model).padding(28).background(Theme.canvas), size: nil, to: outputDirectory, name: "popover-\(title)-\(suffix)", appearance: appearance)
            }
            for section in MainSection.allCases {
                let size = section == .home ? MainView.windowSize : CGSize(width: MainView.windowSize.width, height: 1500)
                try write(fixture.mainView(section: section), size: size, to: outputDirectory, name: "main-\(section.rawValue)-\(suffix)", appearance: appearance)
            }
            for (index, view) in fixture.onboardingSteps().enumerated() {
                try write(view, size: OnboardingView.windowSize, to: outputDirectory, name: "onboarding-\(index + 1)-\(suffix)", appearance: appearance)
            }
        }
    }

    private static let popoverStates: [(String, PopoverStatus, String)] = [
        ("ready", .ready, ""),
        ("recording", .recording, ""),
        ("transcribing", .transcribing, "Cleaning up your text"),
        ("loading", .loadingModel(detail: "Downloading the speech model, 42%", progress: 0.42), "Downloading the speech model, 42%"),
        ("permission", .permissionNeeded(.accessibility), PermissionFix.accessibility.detail),
    ]

    private static func write(_ view: some View, size: CGSize?, to directory: URL, name: String, appearance: NSAppearance) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let resolved = size ?? host.fittingSize
        host.frame = NSRect(origin: .zero, size: resolved)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
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
        ), let _ = Optional(rep.size = resolved) else { throw CocoaError(.fileWriteUnknown) }
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
    let historyModel: HistoryModel
    let statsModel: StatsModel
    let vocabularyModel: VocabularyModel
    let analytics = Analytics(enabled: false, installID: UUID())
    let records: [TranscriptRecord]

    init() throws {
        let suite = "com.joelheile.voz.render"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        history = try HistoryStore()
        records = Self.makeRecords()
        for record in records { try history.insert(record) }
        for word in ["Joel", "Parakeet", "GRDB", "Sparkle", "Wispr Flow", "Heil-Escobar"] { try history.vocabulary.add(word, source: .manual) }
        for word in ["Voz", "FluidAudio"] { try history.vocabulary.suggest(word) }
        historyModel = HistoryModel(store: history, copy: { _ in })
        statsModel = StatsModel(store: history)
        vocabularyModel = VocabularyModel(store: history.vocabulary, analytics: analytics)
        status.update(.automatic, .ready(bytes: 483_000_000))
    }

    func popoverModel(status: PopoverStatus, hint: String) -> PopoverModel {
        let model = PopoverModel()
        model.status = status
        model.hint = hint.isEmpty ? Self.hint(for: status, settings: settings) : hint
        model.wordsThisWeek = statsModel.stats.wordsThisWeek
        model.transcripts = Array(records.prefix(3))
        model.canRetry = true
        return model
    }

    func mainView(section: MainSection) -> some View {
        let model = MainWindowModel()
        model.section = section
        return MainView(
            model: model,
            settings: settings,
            status: status,
            history: historyModel,
            stats: statsModel,
            vocabulary: vocabularyModel,
            checkForUpdates: {}
        )
        .frame(width: MainView.windowSize.width)
    }

    func onboardingSteps() -> [AnyView] {
        OnboardingStep.allCases.indices.map { stepIndex in
            let model = OnboardingModel(analytics: analytics, onLanguageChosen: {}, onFinish: {})
            for _ in 0..<stepIndex { model.next() }
            return AnyView(OnboardingView(model: model, settings: settings, modelStatus: status).frame(width: OnboardingView.windowSize.width, height: OnboardingView.windowSize.height))
        }
    }

    private static func hint(for status: PopoverStatus, settings: AppSettings) -> String {
        switch status {
        case .recording: DictationHint.recording(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
        default: DictationHint.idle(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
        }
    }

    private static func makeRecords() -> [TranscriptRecord] {
        let texts = [
            "Let's move the review to Thursday afternoon, and I'll send the agenda tonight.",
            "Remind me to send the invoice before the end of the month.",
            "The build is green again after the dependency bump.",
            "I think we should ship the beta on Friday and watch the crash reports over the weekend.",
            "Can you check whether the new hotkey capture still works with the right option key?",
            "Thanks for the quick turnaround. I'll take another look tomorrow morning.",
        ]
        let apps = ["Xcode", "Slack", "Mail", "Notes", "Safari"]
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

    private static func record(text: String, at date: Date, app: String) -> TranscriptRecord {
        TranscriptRecord(
            createdAt: date,
            rawText: text,
            audioSeconds: Double(text.split(separator: " ").count) / 2.6,
            sttMs: 180,
            totalMs: 420,
            model: "parakeet-tdt-v3",
            appBundleID: nil,
            appName: app,
            fillerWordsRemoved: text.count % 4
        )
    }
}
