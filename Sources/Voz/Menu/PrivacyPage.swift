import SwiftUI

struct PrivacyPage: View {
    private static let copiedLogLines = 200

    @ObservedObject var settings: AppSettings
    let back: () -> Void
    @State private var copiedLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageBar(title: "Privacy", back: back)
            PanelGroup {
                PanelRow(title: "Share usage stats", detail: "Counts and timings, never text or audio") {
                    Toggle("Share usage stats", isOn: $settings.analyticsEnabled).labelsHidden()
                }
                PanelRow(title: "Send crash reports", detail: "Crashes, freezes and error codes, never text or audio") {
                    Toggle("Send crash reports", isOn: $settings.errorReportsEnabled).labelsHidden()
                }
            }
            PanelGroup(title: "Debug log") {
                PanelRow(title: "Include text", detail: "What you said, kept on this Mac") {
                    Toggle("Include text", isOn: $settings.logIncludesText).labelsHidden()
                }
                PanelRow(title: "voz-logs.jsonl") {
                    HStack(spacing: 6) {
                        Button(action: copyLog) {
                            ZStack {
                                crossfading("Copy", visible: !copiedLog)
                                crossfading("Copied", visible: copiedLog)
                            }
                        }
                        .animation(Theme.Motion.section, value: copiedLog)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([DebugLog.shared.file])
                        }
                    }
                    .buttonStyle(.pill(.quiet, .small))
                    .fixedSize()
                }
            }
        }
        .controlSize(.small)
    }

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DebugLog.shared.lastLines(Self.copiedLogLines), forType: .string)
        copiedLog = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedLog = false
        }
    }

    private func crossfading(_ label: String, visible: Bool) -> some View {
        Text(label)
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 2)
    }
}
