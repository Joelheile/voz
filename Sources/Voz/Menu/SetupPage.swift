import SwiftUI

struct SetupPage: View {
    @ObservedObject var model: SetupModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryModel
    let status: PopoverStatus
    let retryModel: () -> Void
    let finish: () -> Void
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepProgress(count: SetupStep.allCases.count, current: model.step.rawValue)
            ZStack(alignment: .topLeading) {
                page
                    .id(model.step)
                    .transition(.page(forward: forward, reduceMotion: reduceMotion))
            }
            footer
        }
    }

    @ViewBuilder
    private var page: some View {
        switch model.step {
        case .access: AccessStep(model: model)
        case .languages: LanguagesStep(settings: settings)
        case .model: ModelStep(settings: settings)
        case .tryIt: TryStep(settings: settings, history: history, status: status, retryModel: retryModel, tried: $model.triedDictation)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.step != .access {
                Button("Back") { go(to: model.step.rawValue - 1) }
                    .buttonStyle(.quietText)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            Button(primaryTitle, action: advance)
                .buttonStyle(.pill(primaryKind, .regular))
                .contentTransition(.interpolate)
                .keyboardShortcut(.defaultAction)
        }
        .animation(Theme.Motion.section, value: model.step)
        .animation(Theme.Motion.section, value: model.allGranted)
    }

    private var primaryTitle: String {
        switch model.step {
        case .access: model.allGranted ? "Continue" : "Skip for now"
        case .languages, .model: "Continue"
        case .tryIt: "Start using Voz"
        }
    }

    private var primaryKind: PillKind {
        model.step == .access && !model.allGranted ? .quiet : .ink
    }

    private func advance() {
        guard model.step != .tryIt else { return finish() }
        go(to: model.step.rawValue + 1)
    }

    private func go(to index: Int) {
        guard let step = SetupStep(rawValue: index) else { return }
        forward = step.rawValue > model.step.rawValue
        withAnimation(.spring(duration: 0.28, bounce: 0)) { model.step = step }
    }
}

struct StepProgress: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< count, id: \.self) { step in
                Capsule()
                    .fill(step <= current ? Theme.ink : Theme.hairline)
                    .frame(width: 20, height: 3)
            }
        }
        .animation(.spring(duration: 0.28, bounce: 0), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

struct StepHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.display(17))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.meta)
                .lineSpacing(2)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AccessStep: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Let Voz hear and type", detail: "Your audio and text never leave this Mac.")
            PanelGroup {
                PermissionRow(title: "Microphone", detail: "To hear your voice", tile: IconTile(.mic, Color(nsColor: .systemPink)), granted: model.microphoneGranted, fix: model.requestMicrophone)
                PermissionRow(title: "Accessibility", detail: "To type at your cursor", tile: IconTile(.accessibility, Color(nsColor: .systemBlue)), granted: model.accessibilityGranted, fix: model.requestAccessibility)
                PermissionRow(title: "Input Monitoring", detail: "To catch your shortcut", tile: IconTile(.keyboard, Color(nsColor: .systemGray)), granted: model.inputMonitoringGranted, fix: model.requestInputMonitoring)
                PermissionRow(title: "System Audio", detail: "To mute music while you talk", tile: IconTile(.volumeX, Color(nsColor: .systemOrange)), granted: model.systemAudioGranted, fix: model.requestSystemAudio)
            }
            .controlSize(.small)
        }
    }
}

private struct LanguagesStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "What do you speak?", detail: "Pick every language you dictate in. Voz keeps your words in them.")
            CappedScrollView(maxHeight: 440) {
                LanguagePicker(selection: $settings.languages)
            }
        }
    }
}

private struct ModelStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Pick a model", detail: "All three run on this Mac. You can switch later.")
            SpeechModelPicker(selection: $settings.speechModel, showsTitle: false)
            PanelGroup {
                PanelRow(title: "Share usage stats", detail: "Timings and totals per known site, tied to a random ID. Anonymous counts always go. Never text or audio") {
                    Toggle("Share usage stats", isOn: $settings.analyticsEnabled).labelsHidden()
                }
            }
            .controlSize(.small)
        }
    }
}

private struct TryStep: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryModel
    let status: PopoverStatus
    let retryModel: () -> Void
    @Binding var triedDictation: Bool
    @StateObject private var capture: HotkeyCapture
    @State private var startedWith: TranscriptRecord.ID?

    init(settings: AppSettings, history: HistoryModel, status: PopoverStatus, retryModel: @escaping () -> Void, tried: Binding<Bool>) {
        self.settings = settings
        self.history = history
        self.status = status
        self.retryModel = retryModel
        _triedDictation = tried
        _capture = StateObject(wrappedValue: HotkeyCapture(settings: settings))
    }

    private var tried: TranscriptRecord? {
        guard let first = history.records.first, first.id != startedWith else { return nil }
        return first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Try it", detail: "Click into any text field and say a sentence.")
            VStack(spacing: 14) {
                KeyCap(text: keyText, pressed: capture.preview != nil, listening: capture.isListening)
                Text(capture.isListening ? "Press your keys, then let go" : DictationHint.idle(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk))
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.interpolate)
                HStack(spacing: 8) {
                    Button(capture.isListening ? "Cancel" : "Change shortcut") {
                        capture.isListening ? capture.cancel() : capture.begin()
                    }
                    .buttonStyle(.pill(.quiet, .small))
                    TabBar(tabs: TalkMode.allCases, selection: settings.talkMode)
                        .frame(width: 120)
                }
                if let warning = capture.warning {
                    Text(warning)
                        .font(.meta)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .groupCard(padding: 0)
            .animation(Theme.Motion.section, value: capture.isListening)
            result
        }
        .onAppear { startedWith = history.records.first?.id }
        .onChange(of: tried?.id) { if tried != nil { triedDictation = true } }
        .onDisappear { capture.cancel() }
    }

    private var placeholder: String {
        switch status {
        case let .loadingModel(detail, _): "\(detail). Try it when it finishes."
        case let .modelFailed(message): "\(message)."
        default: "Your first dictation shows up here."
        }
    }

    private var keyText: String {
        guard capture.isListening else { return settings.hotkey.displayName }
        return capture.preview?.displayName ?? "Press keys"
    }

    private var result: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let tried {
                Icon(.circleCheck, size: 15)
                    .foregroundStyle(Theme.accent)
                    .popIn()
                Text(tried.finalText)
                    .font(.ui(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .transition(.opacity)
            } else {
                Text(placeholder)
                    .font(.ui(13))
                    .foregroundStyle(Theme.inkTertiary)
                    .contentTransition(.numericText())
                if case .modelFailed = status {
                    Spacer(minLength: 0)
                    Button("Try again", action: retryModel)
                        .buttonStyle(.pill(.quiet, .small))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .animation(.spring(duration: 0.28, bounce: 0.2), value: tried?.id)
    }
}

private struct KeyCap: View {
    let text: String
    let pressed: Bool
    let listening: Bool

    var body: some View {
        Text(text)
            .font(.ui(15, weight: .medium))
            .foregroundStyle(listening && !pressed ? Theme.inkTertiary : Theme.ink)
            .contentTransition(.interpolate)
            .padding(.horizontal, 18)
            .frame(minWidth: 64, minHeight: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .strokeBorder(listening ? Theme.accent : Theme.hairline, lineWidth: listening ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(pressed ? 0 : 0.08), radius: 0, y: pressed ? 0 : 2)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.spring(duration: 0.15, bounce: 0), value: pressed)
            .animation(.spring(duration: 0.25, bounce: 0), value: text)
    }
}
