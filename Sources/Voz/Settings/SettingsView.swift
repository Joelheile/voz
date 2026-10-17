import SwiftUI
import VozCore

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: ModelStatus
    let checkForUpdates: () -> Void
    @StateObject private var capture: HotkeyCapture

    init(settings: AppSettings, status: ModelStatus, checkForUpdates: @escaping () -> Void) {
        self.settings = settings
        self.status = status
        self.checkForUpdates = checkForUpdates
        _capture = StateObject(wrappedValue: HotkeyCapture(settings: settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            PageHeader(title: "Settings")
            dictation
            speech
            output
            PermissionsGroup()
            general
        }
        .toggleStyle(.switch)
        .onDisappear { capture.cancel() }
    }

    private var dictation: some View {
        SettingGroup(title: "Dictation") {
            SettingRow(title: "Shortcut", detail: capture.warning ?? "Click the shortcut, then press the key or combination you want.") {
                Button(capture.isListening ? "Press a key…" : settings.hotkey.displayName) {
                    capture.isListening ? capture.cancel() : capture.begin()
                }
                .buttonStyle(.pill(capture.isListening ? .accent : .quiet, height: 32))
            }
            SettingRow(title: "Mode", detail: settings.holdToTalk ? "Hold the shortcut while you speak." : "Tap once to start and again to stop.") {
                Picker("Mode", selection: $settings.holdToTalk) {
                    Text("Tap").tag(false)
                    Text("Hold").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
            SettingRow(title: "Clean up text", detail: "Removes filler words and fixes punctuation on your Mac.") {
                Toggle("Clean up text", isOn: $settings.cleanupEnabled).labelsHidden()
            }
        }
    }

    private var speech: some View {
        SettingGroup(title: "Speech") {
            SettingRow(title: "Language", detail: "Only the model you pick is downloaded.") {
                Picker("Language", selection: $settings.languageMode) {
                    ForEach(LanguageMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            SettingRow(title: "Speech model") {
                ModelStatusLabel(status: status, mode: settings.languageMode)
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var output: some View {
        SettingGroup(title: "Output") {
            SettingRow(title: "Copy to clipboard", detail: "Keep the last dictation on the clipboard.") {
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboard).labelsHidden()
            }
            SettingRow(title: "Insert into app", detail: "Type the text where your cursor is. Needs Accessibility.") {
                Toggle("Insert into app", isOn: $settings.insertIntoApp).labelsHidden()
            }
            SettingRow(title: "Mute while recording", detail: "Silences other audio while you speak.") {
                Toggle("Mute while recording", isOn: $settings.muteWhileRecording).labelsHidden()
            }
            SettingRow(title: "Sound cues", detail: "Play a short sound when recording starts and stops.") {
                Toggle("Sound cues", isOn: $settings.soundCues).labelsHidden()
            }
            SettingRow(title: "Indicator", detail: "Where the recording indicator appears.") {
                Picker("Indicator", selection: $settings.indicatorStyle) {
                    ForEach(IndicatorStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
        }
    }

    private var general: some View {
        SettingGroup(title: "General") {
            SettingRow(title: "Launch at login") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin).labelsHidden()
            }
            SettingRow(title: "Share anonymous usage stats", detail: "Counts and timings only. Never text or audio.") {
                Toggle("Share anonymous usage stats", isOn: $settings.analyticsEnabled).labelsHidden()
            }
            SettingRow(title: "Beta updates", detail: "Get early builds before stable releases.") {
                Toggle("Beta updates", isOn: $settings.receiveBetaUpdates).labelsHidden()
            }
            SettingRow(title: "Updates", detail: "Version \(Self.version)") {
                Button("Check for updates", action: checkForUpdates)
                    .buttonStyle(.pill(.quiet, height: 32))
            }
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

private struct PermissionsGroup: View {
    @State private var microphone = Permissions.microphoneStatus
    @State private var accessibility = Permissions.accessibilityGranted
    @State private var inputMonitoring = Permissions.inputMonitoringGranted

    var body: some View {
        SettingGroup(title: "Permissions") {
            PermissionRow(title: "Microphone", detail: "Hears you while you dictate.", granted: microphone == .authorized) {
                if microphone == .notDetermined {
                    Task { await Permissions.requestMicrophone() }
                } else {
                    Permissions.openSettings(pane: "Privacy_Microphone")
                }
            }
            PermissionRow(title: "Accessibility", detail: "Types the text into the app you are using.", granted: accessibility) {
                Permissions.promptForAccessibility()
            }
            PermissionRow(title: "Input Monitoring", detail: "Notices your shortcut while other apps are in front.", granted: inputMonitoring) {
                Permissions.requestInputMonitoring()
                Permissions.openSettings(pane: "Privacy_ListenEvent")
            }
        }
        .task {
            while !Task.isCancelled {
                microphone = Permissions.microphoneStatus
                accessibility = Permissions.accessibilityGranted
                inputMonitoring = Permissions.inputMonitoringGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let fix: () -> Void

    var body: some View {
        SettingRow(title: title, detail: detail) {
            if granted {
                Label("Allowed", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                Button("Allow", action: fix).buttonStyle(.pill(.accent, height: 30))
            }
        }
    }
}
