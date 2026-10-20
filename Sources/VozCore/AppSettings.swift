import Combine
import Foundation

private enum SettingsKey {
    static let hotkey = "hotkey"
    static let holdToTalk = "holdToTalk"
    static let muteWhileRecording = "muteWhileRecording"
    static let copyToClipboard = "copyToClipboard"
    static let insertIntoApp = "insertIntoApp"
    static let speechModel = "speechModel"
    static let soundCues = "soundCues"
    static let launchAtLogin = "launchAtLogin"
    static let onboardingCompleted = "onboardingCompleted"
    static let cleanupEnabled = "cleanupEnabled"
    static let analyticsEnabled = "analyticsEnabled"
    static let receiveBetaUpdates = "receiveBetaUpdates"
    static let versionPingEnabled = "versionPingEnabled"
    static let cleanupPrompt = "cleanupPrompt"
}

@MainActor
public final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published public var hotkey: Hotkey {
        didSet { store(hotkey) }
    }
    @Published public var holdToTalk: Bool {
        didSet { defaults.set(holdToTalk, forKey: SettingsKey.holdToTalk) }
    }
    @Published public var muteWhileRecording: Bool {
        didSet { defaults.set(muteWhileRecording, forKey: SettingsKey.muteWhileRecording) }
    }
    @Published public var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: SettingsKey.copyToClipboard) }
    }
    @Published public var insertIntoApp: Bool {
        didSet { defaults.set(insertIntoApp, forKey: SettingsKey.insertIntoApp) }
    }
    @Published public var speechModel: SpeechModel {
        didSet { defaults.set(speechModel.rawValue, forKey: SettingsKey.speechModel) }
    }
    @Published public var soundCues: Bool {
        didSet { defaults.set(soundCues, forKey: SettingsKey.soundCues) }
    }
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: SettingsKey.launchAtLogin) }
    }
    @Published public var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: SettingsKey.onboardingCompleted) }
    }
    @Published public var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: SettingsKey.cleanupEnabled) }
    }
    @Published public var analyticsEnabled: Bool {
        didSet { defaults.set(analyticsEnabled, forKey: SettingsKey.analyticsEnabled) }
    }
    @Published public var receiveBetaUpdates: Bool {
        didSet { defaults.set(receiveBetaUpdates, forKey: SettingsKey.receiveBetaUpdates) }
    }
    @Published public var versionPingEnabled: Bool {
        didSet { defaults.set(versionPingEnabled, forKey: SettingsKey.versionPingEnabled) }
    }
    @Published public var cleanupPrompt: String {
        didSet {
            if cleanupPrompt == CleanupPrompt.standard {
                defaults.removeObject(forKey: SettingsKey.cleanupPrompt)
            } else {
                defaults.set(cleanupPrompt, forKey: SettingsKey.cleanupPrompt)
            }
        }
    }
    @Published public var isCapturingHotkey = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            SettingsKey.holdToTalk: false,
            SettingsKey.muteWhileRecording: true,
            SettingsKey.copyToClipboard: true,
            SettingsKey.insertIntoApp: true,
            SettingsKey.speechModel: SpeechModel.parakeetV3.rawValue,
            SettingsKey.soundCues: false,
            SettingsKey.launchAtLogin: true,
            SettingsKey.onboardingCompleted: false,
            SettingsKey.cleanupEnabled: true,
            SettingsKey.analyticsEnabled: false,
            SettingsKey.receiveBetaUpdates: false,
            SettingsKey.versionPingEnabled: true,
        ])
        hotkey = defaults.data(forKey: SettingsKey.hotkey)
            .flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) } ?? .rightCommand
        holdToTalk = defaults.bool(forKey: SettingsKey.holdToTalk)
        muteWhileRecording = defaults.bool(forKey: SettingsKey.muteWhileRecording)
        copyToClipboard = defaults.bool(forKey: SettingsKey.copyToClipboard)
        insertIntoApp = defaults.bool(forKey: SettingsKey.insertIntoApp)
        speechModel = defaults.string(forKey: SettingsKey.speechModel).flatMap(SpeechModel.init) ?? .parakeetV3
        soundCues = defaults.bool(forKey: SettingsKey.soundCues)
        launchAtLogin = defaults.bool(forKey: SettingsKey.launchAtLogin)
        onboardingCompleted = defaults.bool(forKey: SettingsKey.onboardingCompleted)
        cleanupEnabled = defaults.bool(forKey: SettingsKey.cleanupEnabled)
        analyticsEnabled = defaults.bool(forKey: SettingsKey.analyticsEnabled)
        receiveBetaUpdates = defaults.bool(forKey: SettingsKey.receiveBetaUpdates)
        versionPingEnabled = defaults.bool(forKey: SettingsKey.versionPingEnabled)
        cleanupPrompt = defaults.string(forKey: SettingsKey.cleanupPrompt) ?? CleanupPrompt.standard
    }

    private func store(_ hotkey: Hotkey) {
        do {
            defaults.set(try JSONEncoder().encode(hotkey), forKey: SettingsKey.hotkey)
        } catch {
            fatalError("Hotkey encoding failed: \(error)")
        }
    }
}
