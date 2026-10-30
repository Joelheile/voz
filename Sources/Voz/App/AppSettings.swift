import Combine
import Foundation

private enum SettingsKey {
    static let hotkey = "hotkey"
    static let holdToTalk = "holdToTalk"
    static let muteWhileRecording = "muteWhileRecording"
    static let copyToClipboard = "copyToClipboard"
    static let insertIntoApp = "insertIntoApp"
    static let soundCues = "soundCues"
    static let livePreviewEnabled = "livePreviewEnabled"
    static let launchAtLogin = "launchAtLogin"
    static let onboardingCompleted = "onboardingCompleted"
    static let cleanupEnabled = "cleanupEnabled"
    static let analyticsEnabled = "analyticsEnabled"
    static let receiveBetaUpdates = "receiveBetaUpdates"
    static let errorReportsEnabled = "errorReportsEnabled"
    static let cleanupPrompt = "cleanupPrompt"
    static let starPromptDismissed = "starPromptDismissed"
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var hotkey: Hotkey {
        didSet { store(hotkey) }
    }
    @Published var holdToTalk: Bool {
        didSet { defaults.set(holdToTalk, forKey: SettingsKey.holdToTalk) }
    }
    @Published var muteWhileRecording: Bool {
        didSet { defaults.set(muteWhileRecording, forKey: SettingsKey.muteWhileRecording) }
    }
    @Published var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: SettingsKey.copyToClipboard) }
    }
    @Published var insertIntoApp: Bool {
        didSet { defaults.set(insertIntoApp, forKey: SettingsKey.insertIntoApp) }
    }
    @Published var speechModel: String {
        didSet { storePipeline() }
    }
    @Published var cleanupModel: String {
        didSet { storePipeline() }
    }
    @Published var cleanupSteps: [String] {
        didSet { storePipeline() }
    }
    @Published private(set) var pipelineError: String?
    @Published var soundCues: Bool {
        didSet { defaults.set(soundCues, forKey: SettingsKey.soundCues) }
    }
    @Published var livePreviewEnabled: Bool {
        didSet { defaults.set(livePreviewEnabled, forKey: SettingsKey.livePreviewEnabled) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: SettingsKey.launchAtLogin) }
    }
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: SettingsKey.onboardingCompleted) }
    }
    @Published var starPromptDismissed: Bool {
        didSet { defaults.set(starPromptDismissed, forKey: SettingsKey.starPromptDismissed) }
    }
    @Published var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: SettingsKey.cleanupEnabled) }
    }
    @Published var analyticsEnabled: Bool {
        didSet { defaults.set(analyticsEnabled, forKey: SettingsKey.analyticsEnabled) }
    }
    @Published var receiveBetaUpdates: Bool {
        didSet { defaults.set(receiveBetaUpdates, forKey: SettingsKey.receiveBetaUpdates) }
    }
    @Published var errorReportsEnabled: Bool {
        didSet { defaults.set(errorReportsEnabled, forKey: SettingsKey.errorReportsEnabled) }
    }
    @Published var cleanupPrompt: String {
        didSet {
            if cleanupPrompt == CleanupPrompt.standard {
                defaults.removeObject(forKey: SettingsKey.cleanupPrompt)
            } else {
                defaults.set(cleanupPrompt, forKey: SettingsKey.cleanupPrompt)
            }
        }
    }
    @Published var isCapturingHotkey = false
    private let home: VozHome
    private var loadingPipeline = false

    var localSpeechModel: SpeechModel {
        SpeechModel(rawValue: speechModel) ?? .parakeetUltra
    }

    var pipelineChoices: PipelineChoices {
        PipelineChoices(speechModel: speechModel, cleanupModel: cleanupModel, cleanupSteps: cleanupSteps)
    }

    init(defaults: UserDefaults = .standard, home: VozHome = VozHome()) {
        self.defaults = defaults
        self.home = home
        defaults.register(defaults: [
            SettingsKey.holdToTalk: false,
            SettingsKey.muteWhileRecording: true,
            SettingsKey.copyToClipboard: true,
            SettingsKey.insertIntoApp: true,
            SettingsKey.soundCues: false,
            SettingsKey.livePreviewEnabled: false,
            SettingsKey.launchAtLogin: true,
            SettingsKey.onboardingCompleted: false,
            SettingsKey.cleanupEnabled: true,
            SettingsKey.analyticsEnabled: false,
            SettingsKey.receiveBetaUpdates: false,
            SettingsKey.errorReportsEnabled: true,
        ])
        hotkey = defaults.data(forKey: SettingsKey.hotkey)
            .flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) } ?? .rightCommand
        holdToTalk = defaults.bool(forKey: SettingsKey.holdToTalk)
        muteWhileRecording = defaults.bool(forKey: SettingsKey.muteWhileRecording)
        copyToClipboard = defaults.bool(forKey: SettingsKey.copyToClipboard)
        insertIntoApp = defaults.bool(forKey: SettingsKey.insertIntoApp)
        soundCues = defaults.bool(forKey: SettingsKey.soundCues)
        livePreviewEnabled = defaults.bool(forKey: SettingsKey.livePreviewEnabled)
        launchAtLogin = defaults.bool(forKey: SettingsKey.launchAtLogin)
        onboardingCompleted = defaults.bool(forKey: SettingsKey.onboardingCompleted)
        starPromptDismissed = defaults.bool(forKey: SettingsKey.starPromptDismissed)
        cleanupEnabled = defaults.bool(forKey: SettingsKey.cleanupEnabled)
        analyticsEnabled = defaults.bool(forKey: SettingsKey.analyticsEnabled)
        receiveBetaUpdates = defaults.bool(forKey: SettingsKey.receiveBetaUpdates)
        errorReportsEnabled = defaults.bool(forKey: SettingsKey.errorReportsEnabled)
        cleanupPrompt = defaults.string(forKey: SettingsKey.cleanupPrompt) ?? CleanupPrompt.standard
        let choices = PipelineChoices.standard
        speechModel = choices.speechModel
        cleanupModel = choices.cleanupModel
        cleanupSteps = choices.cleanupSteps
        reloadPipeline()
    }

    func reloadPipeline() {
        let choices: PipelineChoices
        do {
            choices = try home.pipelineChoices()
            pipelineError = nil
        } catch {
            pipelineError = String(describing: error)
            return
        }
        guard choices != pipelineChoices else { return }
        loadingPipeline = true
        defer { loadingPipeline = false }
        speechModel = choices.speechModel
        cleanupModel = choices.cleanupModel
        cleanupSteps = choices.cleanupSteps
    }

    private func storePipeline() {
        guard !loadingPipeline else { return }
        do {
            try home.setPipelineChoices(pipelineChoices)
            pipelineError = nil
        } catch {
            pipelineError = String(describing: error)
        }
    }

    private func store(_ hotkey: Hotkey) {
        do {
            defaults.set(try JSONEncoder().encode(hotkey), forKey: SettingsKey.hotkey)
        } catch {
            fatalError("Hotkey encoding failed: \(error)")
        }
    }
}

enum UpdateChannel: String, Sendable {
    case stable
    case beta
    case dev

    init(version: String) {
        if version.contains("-dev") {
            self = .dev
        } else {
            self = version.contains("-beta") ? .beta : .stable
        }
    }

    /// Dev builds carry build number 1, so any release looks newer and would replace them.
    var checksInBackground: Bool { self != .dev }
}

enum AppStorage {
    static let directoryPermissions = 0o700
    static let filePermissions = 0o600

    static func directory() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("voz", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        try FileManager.default.setAttributes([.posixPermissions: directoryPermissions], ofItemAtPath: directory.path)
        return directory
    }

    static func restrict(fileAt path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: filePermissions], ofItemAtPath: path)
    }
}
