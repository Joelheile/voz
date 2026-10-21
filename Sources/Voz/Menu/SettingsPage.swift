import SwiftUI
import VozCore

struct SettingsPage: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: ModelStatus
    @ObservedObject var vocabulary: VocabularyModel
    @StateObject private var capture: HotkeyCapture
    @State private var microphone = Permissions.microphoneStatus
    @State private var accessibility = Permissions.accessibilityGranted
    @State private var inputMonitoring = Permissions.inputMonitoringGranted

    private var allGranted: Bool {
        microphone == .authorized && accessibility && inputMonitoring
    }

    init(model: PopoverModel, settings: AppSettings, status: ModelStatus, vocabulary: VocabularyModel) {
        self.model = model
        self.settings = settings
        self.status = status
        self.vocabulary = vocabulary
        _capture = StateObject(wrappedValue: HotkeyCapture(settings: settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Settings", back: model.goBack)
            CappedScrollView(maxHeight: 520) {
                VStack(alignment: .leading, spacing: 16) {
                    dictation
                    output
                    if !allGranted { permissions }
                    general
                }
            }
        }
        .controlSize(.small)
        .onDisappear { capture.cancel() }
        .task {
            while !Task.isCancelled {
                microphone = Permissions.microphoneStatus
                accessibility = Permissions.accessibilityGranted
                inputMonitoring = Permissions.inputMonitoringGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var dictation: some View {
        PanelGroup(title: "Dictation") {
            PanelRow(title: "Shortcut", detail: capture.warning) {
                Button(capture.isListening ? capture.preview?.displayName ?? "Press keys…" : settings.hotkey.displayName) {
                    capture.isListening ? capture.cancel() : capture.begin()
                }
                .buttonStyle(.pill(capture.isListening ? .accent : .quiet, height: 28))
            }
            PanelRow(title: "Mode", detail: settings.holdToTalk ? "Hold to speak, release to stop" : "Tap to start, tap again to stop") {
                Picker("Mode", selection: $settings.holdToTalk) {
                    Text("Tap").tag(false)
                    Text("Hold").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SpeechModelPicker(selection: $settings.speechModel, status: status)
            PanelRow(title: "Clean up text", detail: "Drops filler words and fixes punctuation") {
                Toggle("Clean up text", isOn: $settings.cleanupEnabled).labelsHidden()
            }
            if settings.cleanupEnabled {
                LinkRow(title: "Cleanup prompt", value: settings.cleanupPrompt == CleanupPrompt.standard ? "Default" : "Edited") { model.page = .cleanupPrompt }
            }
            LinkRow(title: "Dictionary", value: vocabulary.snapshot.words.count.formatted()) { model.page = .dictionary }
        }
    }

    private var output: some View {
        PanelGroup(title: "Output") {
            PanelRow(title: "Insert into app", detail: "Types at your cursor") {
                Toggle("Insert into app", isOn: $settings.insertIntoApp).labelsHidden()
            }
            PanelRow(title: "Copy to clipboard", detail: "Keeps the last transcript on the clipboard") {
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboard).labelsHidden()
            }
            PanelRow(title: "Mute while recording") {
                Toggle("Mute while recording", isOn: $settings.muteWhileRecording).labelsHidden()
            }
            PanelRow(title: "Sound cues") {
                Toggle("Sound cues", isOn: $settings.soundCues).labelsHidden()
            }
        }
    }

    private var permissions: some View {
        PanelGroup(title: "Permissions") {
            PermissionRow(title: "Microphone", granted: microphone == .authorized) {
                if microphone == .notDetermined {
                    Task { await Permissions.requestMicrophone() }
                } else {
                    Permissions.openSettings(.microphone)
                }
            }
            PermissionRow(title: "Accessibility", granted: accessibility) {
                Permissions.promptForAccessibility()
            }
            PermissionRow(title: "Input Monitoring", granted: inputMonitoring) {
                Permissions.requestInputMonitoring()
                Permissions.openSettings(.inputMonitoring)
            }
        }
    }

    private var general: some View {
        PanelGroup(title: "General") {
            PanelRow(title: "Launch at login") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin).labelsHidden()
            }
            PanelRow(title: "Share anonymous usage stats", detail: "Counts and timings, never text or audio") {
                Toggle("Share anonymous usage stats", isOn: $settings.analyticsEnabled).labelsHidden()
            }
            PanelRow(title: "Send version on install and update", detail: "Version number only, no ID") {
                Toggle("Send version on install and update", isOn: $settings.versionPingEnabled).labelsHidden()
            }
            PanelRow(title: "Beta updates") {
                Toggle("Beta updates", isOn: $settings.receiveBetaUpdates).labelsHidden()
            }
            PanelRow(title: "Version \(Self.version)") {
                Button("Check for updates", action: model.actions.checkForUpdates)
                    .buttonStyle(.pill(.quiet, height: 28))
            }
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

struct PermissionRow: View {
    let title: String
    var detail: String?
    let granted: Bool
    let fix: () -> Void

    var body: some View {
        PanelRow(title: title, detail: detail) {
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                    .help("Allowed")
                    .transition(.symbolEffect(.drawOn))
            } else {
                Button("Allow", action: fix)
                    .buttonStyle(.pill(.accent, height: 26))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.15), value: granted)
    }
}
