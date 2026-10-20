import SwiftUI
import VozCore

struct SetupPage: View {
    @ObservedObject var model: SetupModel
    @ObservedObject var settings: AppSettings
    let finish: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up Voz")
                .font(.display(22))
                .foregroundStyle(Theme.ink)
                .entrance(0, appeared: appeared, reduceMotion: reduceMotion)
            PanelGroup {
                PermissionRow(title: "Microphone, to hear you", granted: model.microphoneGranted, fix: model.requestMicrophone)
                PermissionRow(title: "Accessibility, to type for you", granted: model.accessibilityGranted, fix: model.requestAccessibility)
                PermissionRow(title: "Input Monitoring, for your shortcut", granted: model.inputMonitoringGranted, fix: model.requestInputMonitoring)
            }
            .entrance(1, appeared: appeared, reduceMotion: reduceMotion)
            PanelGroup {
                SpeechModelPicker(selection: $settings.speechModel)
                PanelRow(title: "Share anonymous usage stats") {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkTertiary)
                            .help("Counts and timings, never text or audio")
                        Toggle("Share anonymous usage stats", isOn: $settings.analyticsEnabled).labelsHidden()
                    }
                }
            }
            .controlSize(.small)
            .entrance(2, appeared: appeared, reduceMotion: reduceMotion)
            HStack(spacing: 12) {
                Text(DictationHint.idle(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk))
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 0)
                Button("Done", action: finish)
                    .buttonStyle(.pill(model.allGranted ? .accent : .quiet, height: 32))
                    .animation(Theme.Motion.section, value: model.allGranted)
                    .keyboardShortcut(.defaultAction)
            }
            .entrance(3, appeared: appeared, reduceMotion: reduceMotion)
        }
        .onAppear { appeared = true }
    }
}

private extension View {
    func entrance(_ index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 6)
            .animation(.spring(duration: 0.35, bounce: 0).delay(Double(index) * 0.05), value: appeared)
    }
}
