import SwiftUI

struct AIModelPage: View {
    @ObservedObject var settings: AppSettings
    let back: () -> Void
    @State private var claudeKey = ""
    @State private var working: Task<Void, Never>?
    @State private var pending: AIProvider?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "AI model", back: back)
            PageNote(text: "Extensions such as Reply and Edit write with this model. ChatGPT and Claude write better and get the text you send them. Apple's runs on your Mac and costs nothing.")
            PanelGroup {
                PanelRow(title: "ChatGPT", detail: settings.aiModel == .chatgpt ? settings.aiAccount : "Uses your Plus or Pro plan") {
                    choose(.chatgpt, label: pending == .chatgpt ? "Waiting for browser…" : "Continue with ChatGPT") {
                        run(.chatgpt) { _ = try await AIModels.signInToChatGPT(settings) }
                    }
                }
                PanelRow(title: "Claude", detail: settings.aiModel == .claude ? "Your API key" : "Max, Ultra and Team include credits") {
                    if settings.aiModel == .claude {
                        selectedMark
                    } else {
                        SecureField("API key", text: $claudeKey)
                            .textFieldStyle(.plain)
                            .font(.meta)
                            .foregroundStyle(Theme.ink)
                            .onSubmit(useClaude)
                            .frame(width: 88)
                            .fieldBackground(.small)
                        Button("Use", action: useClaude)
                            .buttonStyle(.pill(.quiet, .small))
                            .disabled(claudeKey.isEmpty || pending != nil)
                    }
                }
                PanelRow(title: "Apple", detail: "On your Mac, free and private") {
                    choose(.apple) { run(.apple) { await AIModels.useApple(settings) } }
                }
            }
            .animation(Theme.Motion.section, value: settings.aiModel)
            if let error {
                Text(error)
                    .font(.meta)
                    .foregroundStyle(Theme.failure)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { working?.cancel() }
    }

    private var selectedMark: some View {
        Icon(.circleCheck, size: 15)
            .foregroundStyle(Theme.accent)
            .help("In use")
            .popIn()
    }

    @ViewBuilder
    private func choose(_ provider: AIProvider, label: String = "Use", action: @escaping () -> Void) -> some View {
        if settings.aiModel == provider {
            selectedMark
        } else {
            Button(label) {
                if pending == provider { working?.cancel() } else { action() }
            }
            .buttonStyle(.pill(provider == .chatgpt ? .accent : .quiet, .small))
            .fixedSize()
            .disabled(pending != nil && pending != provider)
        }
    }

    private func useClaude() {
        let key = claudeKey
        run(.claude) {
            try await AIModels.useClaude(key: key, settings)
            claudeKey = ""
        }
    }

    private func run(_ provider: AIProvider, _ change: @escaping @MainActor () async throws -> Void) {
        error = nil
        pending = provider
        working = Task {
            do {
                try await change()
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            working = nil
            pending = nil
        }
    }
}
