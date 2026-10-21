import SwiftUI
import VozCore

struct SetupPage: View {
    @ObservedObject var model: SetupModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryModel
    let finish: () -> Void
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepProgress(current: model.step)
            ZStack(alignment: .topLeading) {
                page
                    .id(model.step)
                    .transition(pageTransition)
            }
            footer
        }
    }

    @ViewBuilder
    private var page: some View {
        switch model.step {
        case .access: AccessStep(model: model)
        case .model: ModelStep(settings: settings)
        case .tryIt: TryStep(settings: settings, history: history)
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance: CGFloat = forward ? 24 : -24
        return .asymmetric(
            insertion: .offset(x: distance).combined(with: .opacity),
            removal: .offset(x: -distance).combined(with: .opacity)
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.step != .access {
                Button("Back") { go(to: model.step.rawValue - 1) }
                    .font(.ui(13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .buttonStyle(.pressable(0.97))
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            Button(primaryTitle, action: advance)
                .buttonStyle(.pill(primaryKind, height: 32))
                .contentTransition(.interpolate)
                .keyboardShortcut(.defaultAction)
        }
        .animation(Theme.Motion.section, value: model.step)
        .animation(Theme.Motion.section, value: model.allGranted)
    }

    private var primaryTitle: String {
        switch model.step {
        case .access: model.allGranted ? "Continue" : "Skip for now"
        case .model: "Continue"
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
        withAnimation(.spring(duration: 0.32, bounce: 0)) { model.step = step }
    }
}

private struct StepProgress: View {
    let current: SetupStep

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SetupStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= current.rawValue ? Theme.ink : Theme.hairline)
                    .frame(width: 20, height: 3)
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue + 1) of \(SetupStep.allCases.count)")
    }
}

private struct StepHeader: View {
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
                PermissionRow(title: "Microphone", detail: "To hear your voice", granted: model.microphoneGranted, fix: model.requestMicrophone)
                PermissionRow(title: "Accessibility", detail: "To type at your cursor", granted: model.accessibilityGranted, fix: model.requestAccessibility)
                PermissionRow(title: "Input Monitoring", detail: "To catch your shortcut", granted: model.inputMonitoringGranted, fix: model.requestInputMonitoring)
            }
            .controlSize(.small)
        }
    }
}

private struct ModelStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Pick a model", detail: "All three run on this Mac. You can switch later.")
            SpeechModelPicker(selection: $settings.speechModel, showsTitle: false)
            Toggle(isOn: $settings.analyticsEnabled) {
                Text("Share anonymous usage stats, never text or audio")
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .toggleStyle(.checkbox)
        }
    }
}

private struct TryStep: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryModel
    @StateObject private var capture: HotkeyCapture
    @State private var startedWith: TranscriptRecord.ID?

    init(settings: AppSettings, history: HistoryModel) {
        self.settings = settings
        self.history = history
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
                    .buttonStyle(.pill(.quiet, height: 28))
                    Picker("Mode", selection: $settings.holdToTalk) {
                        Text("Tap").tag(false)
                        Text("Hold").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
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
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .animation(Theme.Motion.section, value: capture.isListening)
            result
        }
        .onAppear { startedWith = history.records.first?.id }
        .onDisappear { capture.cancel() }
    }

    private var keyText: String {
        guard capture.isListening else { return settings.hotkey.displayName }
        return capture.preview?.displayName ?? "Press keys"
    }

    private var result: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let tried {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .transition(.symbolEffect(.drawOn))
                Text(tried.finalText)
                    .font(.ui(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .transition(.opacity)
            } else {
                Text("Your first dictation shows up here.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .animation(.spring(duration: 0.4, bounce: 0.2), value: tried?.id)
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(listening ? Color.accentColor : Theme.hairline, lineWidth: listening ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(pressed ? 0 : 0.08), radius: 0, y: pressed ? 0 : 2)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.spring(duration: 0.15, bounce: 0), value: pressed)
            .animation(.spring(duration: 0.25, bounce: 0), value: text)
    }
}
