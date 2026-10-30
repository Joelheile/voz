import SwiftUI

struct SettingsPage: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var catalog: ExtensionCatalog
    @StateObject private var capture: HotkeyCapture
    @State private var access: PermissionSnapshot?

    private var allGranted: Bool {
        guard let access else { return true }
        return access.microphone == .authorized && access.accessibility && access.inputMonitoring && (access.systemAudio || !settings.muteWhileRecording)
    }

    init(model: PopoverModel, settings: AppSettings, catalog: ExtensionCatalog) {
        self.model = model
        self.settings = settings
        self.catalog = catalog
        _capture = StateObject(wrappedValue: HotkeyCapture(settings: settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Settings", back: model.goBack) {
                Button("What's new") { model.page = .whatsNew }
                    .buttonStyle(.pill(.quiet, .small))
            }
            CappedScrollView(maxHeight: 640) {
                VStack(alignment: .leading, spacing: 16) {
                    if !allGranted { permissions }
                    dictation
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
        PanelGroup {
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
        PanelGroup(title: "Text") {
            PanelRow(title: "Output") {
                TabBar(tabs: OutputMode.allCases, selection: settings.outputMode)
                    .frame(width: 156)
            }
            LinkRow(title: "Cleanup", value: settings.cleanupEnabled ? "On" : "Off") { model.page = .cleanup }
        }
        PanelGroup(title: "While recording") {
            MicrophonePicker(selection: $settings.microphone)
            toggle("Mute other apps", isOn: $settings.muteWhileRecording)
            toggle("Sound cues", isOn: $settings.soundCues)
        }
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
            LinkRow(title: "Privacy and debug log", value: "") { model.page = .privacy }
            ActionRow(title: "Quit Voz", value: "", action: model.actions.quit)
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
}

enum TalkMode: String, CaseIterable {
    case tap = "Tap"
    case hold = "Hold"
}

enum OutputMode: String, CaseIterable {
    case type = "Type"
    case copy = "Copy"
    case both = "Both"

    init(pastes: Bool, copies: Bool) {
        switch (pastes, copies) {
        case (true, true): self = .both
        case (true, false): self = .type
        case (false, _): self = .copy
        }
    }

    var pastes: Bool { self != .copy }
    var copies: Bool { self != .type }
}

extension AppSettings {
    var talkMode: Binding<TalkMode> {
        Binding { self.holdToTalk ? .hold : .tap } set: { self.holdToTalk = $0 == .hold }
    }

    var outputMode: Binding<OutputMode> {
        Binding { OutputMode(pastes: self.insertIntoApp, copies: self.copyToClipboard) } set: {
            self.insertIntoApp = $0.pastes
            self.copyToClipboard = $0.copies
        }
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
