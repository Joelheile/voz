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
                IconButton(icon: .messageSquare, help: "Feedback") { model.page = .feedback }
                IconButton(icon: .scrollText, help: "What's new") { model.page = .whatsNew }
            }
            CappedScrollView(maxHeight: 640) {
                VStack(alignment: .leading, spacing: 22) {
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
        PanelGroup(title: "Dictation") {
            PanelRow(title: "Shortcut", detail: capture.warning, tile: IconTile(.keyboard, Color(nsColor: .systemGray))) {
                Button(capture.isListening ? capture.preview?.displayName ?? "Press keys…" : settings.hotkey.displayName) {
                    capture.isListening ? capture.cancel() : capture.begin()
                }
                .buttonStyle(.pill(capture.isListening ? .accent : .quiet, .small))
            }
            PanelRow(title: "Mode", tile: IconTile(.hand, Color(nsColor: .systemIndigo))) {
                TabBar(tabs: TalkMode.allCases, selection: settings.talkMode)
                    .frame(width: 120)
            }
            PanelRow(title: "Output", tile: IconTile(.type, Color(nsColor: .systemOrange))) {
                TabBar(tabs: OutputMode.allCases, selection: settings.outputMode)
                    .frame(width: 156)
            }
            PanelRow(title: "Quick send", detail: "Return while talking sends the text", tile: IconTile(.send, Color(nsColor: .systemGreen))) {
                Toggle("Quick send", isOn: $settings.quickSend).labelsHidden()
            }
            .disabled(!settings.insertIntoApp)
            PanelRow(title: "Live preview", detail: "Draft text under the indicator", tile: IconTile(.textCursorInput, Color(nsColor: .systemCyan))) {
                Toggle("Live preview", isOn: $settings.livePreviewEnabled).labelsHidden()
            }
        }
        PanelGroup(title: "Models") {
            LinkRow(title: "Speech model", value: speechModelName, tile: IconTile(.cpu, Color(nsColor: .systemTeal))) { model.page = .speechModel }
            LinkRow(title: "Languages", value: SpeechLanguage.summary(of: settings.languages), tile: IconTile(.globe, Color(nsColor: .systemBlue))) { model.page = .languages }
            LinkRow(title: "Cleanup", value: settings.cleanupEnabled ? "On" : "Off", tile: IconTile(.wandSparkles, Color(nsColor: .systemPurple))) { model.page = .cleanup }
            LinkRow(title: "AI model", value: settings.aiModel.name, tile: IconTile(.bot, Color(nsColor: .systemIndigo))) { model.page = .aiModel }
        }
        PanelGroup(title: "Sound") {
            MicrophonePicker(selection: $settings.microphone, headphoneQuality: $settings.headphoneQuality)
            toggle("Mute apps while dictating", tile: IconTile(.volumeX, Color(nsColor: .systemRed)), isOn: $settings.muteWhileRecording)
            toggle("Sound cues", tile: IconTile(.volume2, Color(nsColor: .systemGreen)), isOn: $settings.soundCues)
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
                    Task {
                        await access.microphone == .notDetermined ? Permissions.requestMicrophone() : Permissions.requestBlockedMicrophone()
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
            toggle("Launch at login", tile: IconTile(.power, Color(nsColor: .systemGray)), isOn: $settings.launchAtLogin)
            LinkRow(title: "Product tour", value: "", tile: IconTile(.play, Color(nsColor: .systemBlue))) { model.page = .tour }
            LinkRow(title: "Privacy and debug log", value: "", tile: IconTile(.shield, Color(nsColor: .systemGreen))) { model.page = .privacy }
            ActionRow(title: "Quit Voz", value: "", tile: IconTile(.logOut, Color(nsColor: .systemGray)), action: model.actions.quit)
        }
    }

    private func allowRow(_ title: String, fix: @escaping () -> Void) -> some View {
        PanelRow(title: title) {
            Button("Allow", action: fix).buttonStyle(.pill(.accent, .small))
        }
    }

    private func toggle(_ title: String, tile: IconTile, isOn: Binding<Bool>) -> some View {
        PanelRow(title: title, tile: tile) {
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
    var tile: IconTile?
    let granted: Bool
    let fix: () -> Void

    var body: some View {
        PanelRow(title: title, detail: detail, tile: tile) {
            if granted {
                Icon(.circleCheck, size: 16)
                    .foregroundStyle(Theme.accent)
                    .help("Allowed")
                    .popIn()
            } else {
                Button("Allow", action: fix)
                    .buttonStyle(.pill(.accent, .small))
                    .popIn(from: 0.9)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.15), value: granted)
    }
}
