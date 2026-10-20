import SwiftUI
import VozCore

struct SetupPage: View {
    @ObservedObject var model: SetupModel
    @ObservedObject var settings: AppSettings
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up Voz")
                    .font(.display(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Three permissions, then you can dictate in any app.")
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }
            PanelGroup {
                PermissionRow(title: "Microphone", detail: "Records only while you dictate", granted: model.microphoneGranted, fix: model.requestMicrophone)
                PermissionRow(title: "Accessibility", detail: "Inserts text at your cursor", granted: model.accessibilityGranted, fix: model.requestAccessibility)
                PermissionRow(title: "Input Monitoring", detail: "Detects your shortcut in other apps", granted: model.inputMonitoringGranted, fix: model.requestInputMonitoring)
            }
            PanelGroup {
                SpeechModelPicker(selection: $settings.speechModel)
                PanelRow(title: "Share anonymous usage stats", detail: "Counts and timings, never text or audio") {
                    Toggle("Share anonymous usage stats", isOn: $settings.analyticsEnabled).labelsHidden()
                }
            }
            .controlSize(.small)
            HStack(spacing: 12) {
                Text(DictationHint.instruction(hotkey: settings.hotkey, holdToTalk: settings.holdToTalk))
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Done", action: finish)
                    .buttonStyle(.pill(.ink, height: 32))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
