import SwiftUI

struct SettingsPage: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: ModelStatus
    @ObservedObject var vocabulary: VocabularyModel
    @ObservedObject var catalog: ExtensionCatalog
    @StateObject private var capture: HotkeyCapture
    @State private var access: PermissionSnapshot?

    private var allGranted: Bool {
        guard let access else { return true }
        return access.microphone == .authorized && access.accessibility && access.inputMonitoring && (access.systemAudio || !settings.muteWhileRecording)
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
            CappedScrollView(maxHeight: 520) {
                VStack(alignment: .leading, spacing: 16) {
                    if !allGranted { permissions }
                    dictation
                    cleanup
                    general
                }
            }
        }
        .controlSize(.small)
        .onDisappear { capture.cancel() }
        .task {
            while !Task.isCancelled {
                let latest = await PermissionSnapshot.read()
                if latest != access { access = latest }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var dictation: some View {
        PanelGroup(title: "Dictation") {
            PanelRow(title: "Shortcut", detail: capture.warning) {
                Button(capture.isListening ? capture.preview?.displayName ?? "Press keys…" : settings.hotkey.displayName) {
                    capture.isListening ? capture.cancel() : capture.begin()
                }
                .buttonStyle(.pill(capture.isListening ? .accent : .quiet, .small))
            }
            PanelRow(title: "Mode") {
                TabBar(tabs: TalkMode.allCases, selection: settings.talkMode)
                    .frame(width: 120)
            }
            LinkRow(title: "Speech model", value: speechModelName) { model.page = .speechModel }
            PanelRow(title: "Live preview", detail: "Draft text under the indicator") {
                Toggle("Live preview", isOn: $settings.livePreviewEnabled).labelsHidden()
            }
        }
        PanelGroup(title: "Output") {
            toggle("Type at cursor", isOn: $settings.insertIntoApp)
            toggle("Copy to clipboard", isOn: $settings.copyToClipboard)
            toggle("Mute other apps", isOn: $settings.muteWhileRecording)
            toggle("Sound cues", isOn: $settings.soundCues)
        }
    }

    @ViewBuilder
    private var cleanup: some View {
        PanelGroup(title: "Cleanup") {
            PanelRow(title: "Clean up text", detail: "Removes filler words, fixes punctuation") {
                Toggle("Clean up text", isOn: $settings.cleanupEnabled).labelsHidden()
            }
            if settings.cleanupEnabled {
                if !catalog.cleanupModels.isEmpty || settings.cleanupModel != CleanupModelID.apple {
                    ModelPicker(title: "Model", selection: $settings.cleanupModel, options: [ModelOption(id: CleanupModelID.apple, name: "Apple", detail: "On device")] + ModelOption.extensions(catalog.cleanupModels))
                }
                LinkRow(title: "Steps", value: edited(stepsEdited)) { model.page = .cleanupSteps }
                LinkRow(title: "Prompt", value: edited(settings.cleanupPrompt != CleanupPrompt.standard)) { model.page = .cleanupPrompt }
            }
            LinkRow(title: "Dictionary", value: vocabulary.snapshot.words.count.formatted()) { model.page = .dictionary }
            if let error = settings.pipelineError {
                PanelRow(title: "Could not read settings.json", detail: error) { EmptyView() }
            }
        }
        .animation(Theme.Motion.section, value: settings.cleanupEnabled)
    }

    private func edited(_ isEdited: Bool) -> String {
        isEdited ? "Edited" : "Default"
    }

    private var stepsEdited: Bool {
        settings.cleanupSteps != CleanupStep.standard
    }

    private var speechModelName: String {
        SpeechModel(rawValue: settings.speechModel)?.name ?? catalog.speechModels.first { $0.id == settings.speechModel }?.name ?? settings.speechModel
    }

    @ViewBuilder
    private var permissions: some View {
        if let access { permissions(access) }
    }

    private func permissions(_ access: PermissionSnapshot) -> some View {
        PanelGroup(title: "Needs access") {
            if access.microphone != .authorized {
                allowRow("Microphone") {
                    if access.microphone == .notDetermined {
                        Task { await Permissions.requestMicrophone() }
                    } else {
                        Permissions.openSettings(.microphone)
                    }
                }
            }
            if !access.accessibility {
                allowRow("Accessibility") { Permissions.requestAccessibility() }
            }
            if !access.inputMonitoring {
                allowRow("Input Monitoring") { Permissions.requestInputMonitoring() }
            }
            if settings.muteWhileRecording && !access.systemAudio {
                allowRow("System Audio") {
                    Task { await Permissions.requestSystemAudio() }
                }
            }
        }
    }

    @ViewBuilder
    private var general: some View {
        PanelGroup(title: "App") {
            toggle("Launch at login", isOn: $settings.launchAtLogin)
            toggle("Beta updates", isOn: $settings.receiveBetaUpdates)
            PanelRow(title: "Version \(Self.version)") {
                Button("Check for updates", action: model.actions.checkForUpdates)
                    .buttonStyle(.pill(.quiet, .small))
            }
        }
        PanelGroup(title: "Privacy") {
            PanelRow(title: "Share usage stats", detail: "Counts and timings, never text or audio") {
                Toggle("Share usage stats", isOn: $settings.analyticsEnabled).labelsHidden()
            }
            PanelRow(title: "Send crash reports", detail: "Crashes, freezes and error codes, never text or audio") {
                Toggle("Send crash reports", isOn: $settings.errorReportsEnabled).labelsHidden()
            }
        }
    }

    private func allowRow(_ title: String, fix: @escaping () -> Void) -> some View {
        PanelRow(title: title) {
            Button("Allow", action: fix).buttonStyle(.pill(.accent, .small))
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

enum TalkMode: String, CaseIterable {
    case tap = "Tap"
    case hold = "Hold"
}

extension AppSettings {
    var talkMode: Binding<TalkMode> {
        Binding { self.holdToTalk ? .hold : .tap } set: { self.holdToTalk = $0 == .hold }
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
                    .foregroundStyle(Theme.accent)
                    .help("Allowed")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Button("Allow", action: fix)
                    .buttonStyle(.pill(.accent, .small))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.15), value: granted)
    }
}
