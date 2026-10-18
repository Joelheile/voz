import Combine
import Foundation

public enum SettingsKey {
    public static let hotkey = "hotkey"
    public static let holdToTalk = "holdToTalk"
    public static let muteWhileRecording = "muteWhileRecording"
    public static let copyToClipboard = "copyToClipboard"
    public static let insertIntoApp = "insertIntoApp"
    public static let speechModel = "speechModel"
    public static let indicatorStyle = "indicatorStyle"
    public static let soundCues = "soundCues"
    public static let launchAtLogin = "launchAtLogin"
    public static let onboardingCompleted = "onboardingCompleted"
    public static let cleanupEnabled = "cleanupEnabled"
    public static let analyticsEnabled = "analyticsEnabled"
    public static let receiveBetaUpdates = "receiveBetaUpdates"
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
    @Published public var indicatorStyle: IndicatorStyle {
        didSet { defaults.set(indicatorStyle.rawValue, forKey: SettingsKey.indicatorStyle) }
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
    @Published public var isCapturingHotkey = false

    public var output: OutputSettings {
        var output = OutputSettings()
        output.copyToClipboard = copyToClipboard
        output.pasteIntoActiveApp = insertIntoApp
        return output
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            SettingsKey.holdToTalk: false,
            SettingsKey.muteWhileRecording: true,
            SettingsKey.copyToClipboard: true,
            SettingsKey.insertIntoApp: true,
            SettingsKey.speechModel: SpeechModel.parakeetUltra.rawValue,
            SettingsKey.indicatorStyle: IndicatorStyle.notch.rawValue,
            SettingsKey.soundCues: false,
            SettingsKey.launchAtLogin: true,
            SettingsKey.onboardingCompleted: false,
            SettingsKey.cleanupEnabled: true,
            SettingsKey.analyticsEnabled: false,
            SettingsKey.receiveBetaUpdates: false,
        ])
        hotkey = defaults.data(forKey: SettingsKey.hotkey)
            .flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) } ?? .rightCommand
        holdToTalk = defaults.bool(forKey: SettingsKey.holdToTalk)
        muteWhileRecording = defaults.bool(forKey: SettingsKey.muteWhileRecording)
        copyToClipboard = defaults.bool(forKey: SettingsKey.copyToClipboard)
        insertIntoApp = defaults.bool(forKey: SettingsKey.insertIntoApp)
        speechModel = defaults.string(forKey: SettingsKey.speechModel).flatMap(SpeechModel.init) ?? .parakeetUltra
        indicatorStyle = defaults.string(forKey: SettingsKey.indicatorStyle).flatMap(IndicatorStyle.init) ?? .notch
        soundCues = defaults.bool(forKey: SettingsKey.soundCues)
        launchAtLogin = defaults.bool(forKey: SettingsKey.launchAtLogin)
        onboardingCompleted = defaults.bool(forKey: SettingsKey.onboardingCompleted)
        cleanupEnabled = defaults.bool(forKey: SettingsKey.cleanupEnabled)
        analyticsEnabled = defaults.bool(forKey: SettingsKey.analyticsEnabled)
        receiveBetaUpdates = defaults.bool(forKey: SettingsKey.receiveBetaUpdates)
    }

    private func store(_ hotkey: Hotkey) {
        do {
            defaults.set(try JSONEncoder().encode(hotkey), forKey: SettingsKey.hotkey)
        } catch {
            fatalError("Hotkey encoding failed: \(error)")
        }
    }
}
