import AVFoundation
import SwiftUI
import VozCore

struct OnboardingView: View {
    static let windowSize = CGSize(width: 560, height: 620)

    @ObservedObject var model: OnboardingModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var modelStatus: ModelStatus

    var body: some View {
        VStack(spacing: 0) {
            StepDots(count: OnboardingStep.allCases.count, current: OnboardingStep.allCases.firstIndex(of: model.step) ?? 0)
                .padding(.top, 44)
            Spacer(minLength: 0)
            content
                .id(model.step)
                .transition(.opacity)
            Spacer(minLength: 0)
            Button(model.isLastStep ? "Finish" : "Continue", action: model.next)
                .buttonStyle(.pill(.ink, height: 46))
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 40)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 56)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .animation(Theme.Motion.section, value: model.step)
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .microphone:
            PermissionStep(
                symbol: "mic",
                title: "Let voz hear you",
                accented: "hear",
                detail: "voz records your voice only while you dictate. Audio never leaves this Mac.",
                granted: model.microphoneStatus == .authorized,
                buttonTitle: model.microphoneStatus == .notDetermined ? "Allow microphone" : "Open System Settings",
                action: model.requestMicrophone
            )
        case .accessibility:
            PermissionStep(
                symbol: "accessibility",
                title: "Let voz type for you",
                accented: "type",
                detail: "voz needs this to type the text into the app you are using.",
                granted: model.accessibilityGranted,
                buttonTitle: "Allow accessibility",
                action: model.requestAccessibility
            )
        case .inputMonitoring:
            PermissionStep(
                symbol: "keyboard",
                title: "Let voz hear your shortcut",
                accented: "shortcut",
                detail: "voz needs this to notice your hotkey while other apps are in front.",
                granted: model.inputMonitoringGranted,
                buttonTitle: "Open System Settings",
                action: model.requestInputMonitoring
            )
        case .language:
            LanguageStep(settings: settings)
        case .analytics:
            AnalyticsStep(settings: settings)
        case .test:
            TestStep(settings: settings, status: modelStatus, text: $model.testText)
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.accent : Theme.selected)
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(Theme.Motion.section, value: current)
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: String
    let accented: String
    let detail: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(width: 68, height: 68)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline))
            accentedTitle
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accentedTitle: Text {
        guard let range = title.range(of: accented) else {
            return Text(title).font(.display(34, weight: .semibold))
        }
        return Text(title[..<range.lowerBound]).font(.display(34, weight: .semibold))
            + Text(title[range]).font(.display(34, weight: .semibold)).italic().foregroundStyle(Theme.accent)
            + Text(title[range.upperBound...]).font(.display(34, weight: .semibold))
    }
}

private struct PermissionStep: View {
    let symbol: String
    let title: String
    let accented: String
    let detail: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            StepHeader(symbol: symbol, title: title, accented: accented, detail: detail)
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .symbolRenderingMode(.palette)
                    .frame(height: 36)
            } else {
                Button(buttonTitle, action: action).buttonStyle(.pill(.accent, height: 36))
            }
        }
    }
}

private struct LanguageStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 28) {
            StepHeader(
                symbol: "globe",
                title: "Automatic or English only?",
                accented: "English only",
                detail: "Automatic understands 25 European languages. English only is tuned for English. Only the one you pick is downloaded."
            )
            Picker("Language", selection: $settings.languageMode) {
                ForEach(LanguageMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
        }
    }
}

private struct AnalyticsStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 28) {
            StepHeader(
                symbol: "chart.bar",
                title: "Share anonymous usage stats",
                accented: "anonymous",
                detail: "No text or audio ever leaves your Mac. voz only sends counts and timings, such as how long a dictation took."
            )
            Toggle("Share anonymous usage stats", isOn: $settings.analyticsEnabled)
                .toggleStyle(.switch)
        }
    }
}

private struct TestStep: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: ModelStatus
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(symbol: "waveform", title: "Try it", accented: "it", detail: instruction)
            TextField("Your words appear here", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(3...)
                .multilineTextAlignment(.leading)
                .padding(16)
                .frame(minHeight: 88, alignment: .topLeading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.hairline))
                .focused($focused)
            ModelStatusLabel(status: status, mode: settings.languageMode)
                .font(.meta)
                .foregroundStyle(Theme.inkSecondary)
        }
        .onAppear { focused = true }
    }

    private var instruction: String {
        DictationHint.instruction(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk)
    }
}
