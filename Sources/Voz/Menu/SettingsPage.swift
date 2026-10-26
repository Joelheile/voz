import SwiftUI

struct SettingsPage: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: ModelStatus
    @ObservedObject var vocabulary: VocabularyModel
    @ObservedObject var catalog: ExtensionCatalog
    @StateObject private var capture: HotkeyCapture
    @State private var microphone = Permissions.microphoneStatus
    @State private var accessibility = Permissions.accessibilityGranted
    @State private var inputMonitoring = Permissions.inputMonitoringGranted
    @State private var systemAudio = Permissions.systemAudioGranted
    @State private var tab = Tab.dictation

    private enum Tab: String, CaseIterable {
        case dictation = "Dictation"
        case output = "Output"
        case general = "General"
    }

    private var allGranted: Bool {
        microphone == .authorized && accessibility && inputMonitoring && (systemAudio || !settings.muteWhileRecording)
    }

    init(model: PopoverModel, settings: AppSettings, status: ModelStatus, vocabulary: VocabularyModel, catalog: ExtensionCatalog) {
        self.model = model
        self.settings = settings
        self.status = status
        self.vocabulary = vocabulary
        self.catalog = catalog
        _capture = StateObject(wrappedValue: HotkeyCapture(settings: settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Settings", back: model.goBack)
            TabBar(tabs: Tab.allCases, selection: $tab)
            CappedScrollView(maxHeight: 520) {
                VStack(alignment: .leading, spacing: 12) {
                    if !allGranted { permissions }
                    switch tab {
                    case .dictation: dictation
                    case .output: output
                    case .general: general
                    }
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
                systemAudio = Permissions.systemAudioGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var dictation: some View {
        PanelGroup {
            PanelRow(title: "Shortcut", detail: capture.warning) {
                Button(capture.isListening ? capture.preview?.displayName ?? "Press keys…" : settings.hotkey.displayName) {
                    capture.isListening ? capture.cancel() : capture.begin()
                }
                .buttonStyle(.pill(capture.isListening ? .accent : .quiet, height: 26))
            }
            PanelRow(title: "Mode") {
                TabBar(tabs: TalkMode.allCases, selection: talkMode)
                    .frame(width: 120)
            }
            LinkRow(title: "Speech model", value: speechModelName) { model.page = .speechModel }
            LinkRow(title: "Dictionary", value: vocabulary.snapshot.words.count.formatted()) { model.page = .dictionary }
        }
        PanelGroup {
            PanelRow(title: "Clean up text", detail: "Removes filler words, fixes punctuation") {
                Toggle("Clean up text", isOn: $settings.cleanupEnabled).labelsHidden()
            }
            if settings.cleanupEnabled {
                if !catalog.cleanupModels.isEmpty || settings.cleanupModel != CleanupModelID.apple {
                    ModelPicker(title: "Cleanup model", selection: $settings.cleanupModel, options: [ModelOption(id: CleanupModelID.apple, name: "Apple", detail: "On device")] + ModelOption.extensions(catalog.cleanupModels))
                }
                LinkRow(title: "Steps", value: settings.cleanupSteps == CleanupStep.standard ? "Default" : "Edited") { model.page = .cleanupSteps }
                LinkRow(title: "Prompt", value: settings.cleanupPrompt == CleanupPrompt.standard ? "Default" : "Edited") { model.page = .cleanupPrompt }
            }
            if let error = settings.pipelineError {
                PanelRow(title: "Could not read settings.json", detail: error) { EmptyView() }
            }
        }
    }

    private enum TalkMode: String, CaseIterable {
        case tap = "Tap"
        case hold = "Hold"
    }

    private var talkMode: Binding<TalkMode> {
        Binding { settings.holdToTalk ? .hold : .tap } set: { settings.holdToTalk = $0 == .hold }
    }

    private var speechModelName: String {
        SpeechModel(rawValue: settings.speechModel)?.name ?? catalog.speechModels.first { $0.id == settings.speechModel }?.name ?? settings.speechModel
    }

    private var output: some View {
        PanelGroup {
            toggle("Type at cursor", isOn: $settings.insertIntoApp)
            toggle("Copy to clipboard", isOn: $settings.copyToClipboard)
            toggle("Mute other apps", isOn: $settings.muteWhileRecording)
            toggle("Sound cues", isOn: $settings.soundCues)
        }
    }

    private var permissions: some View {
        PanelGroup(title: "Needs access") {
            if microphone != .authorized {
                allowRow("Microphone") {
                    if microphone == .notDetermined {
                        Task { await Permissions.requestMicrophone() }
                    } else {
                        Permissions.openSettings(.microphone)
                    }
                }
            }
            if !accessibility {
                allowRow("Accessibility") { Permissions.requestAccessibility() }
            }
            if !inputMonitoring {
                allowRow("Input Monitoring") { Permissions.requestInputMonitoring() }
            }
            if settings.muteWhileRecording && !systemAudio {
                allowRow("System Audio") {
                    Task { await Permissions.requestSystemAudio() }
                }
            }
        }
    }

    @ViewBuilder
    private var general: some View {
        PanelGroup {
            toggle("Launch at login", isOn: $settings.launchAtLogin)
            toggle("Beta updates", isOn: $settings.receiveBetaUpdates)
            PanelRow(title: "Version \(Self.version)") {
                Button("Check for updates", action: model.actions.checkForUpdates)
                    .buttonStyle(.pill(.quiet, height: 26))
            }
        }
        PanelGroup(title: "Privacy") {
            PanelRow(title: "Share usage stats", detail: "Counts and timings, never text or audio") {
                Toggle("Share usage stats", isOn: $settings.analyticsEnabled).labelsHidden()
            }
        }
    }

    private func allowRow(_ title: String, fix: @escaping () -> Void) -> some View {
        PanelRow(title: title) {
            Button("Allow", action: fix).buttonStyle(.pill(.accent, height: 26))
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        PanelRow(title: title) {
            Toggle(title, isOn: isOn).labelsHidden()
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
                Icon(.circleCheck, size: 16)
                    .foregroundStyle(Color.accentColor)
                    .help("Allowed")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Button("Allow", action: fix)
                    .buttonStyle(.pill(.accent, height: 26))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.15), value: granted)
    }
}
