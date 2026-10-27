import SwiftUI

struct CleanupStepsPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var catalog: ExtensionCatalog
    let back: () -> Void

    private var available: [String] {
        CleanupStep.standard + catalog.cleanupSteps.map(\.id)
    }

    private var off: [String] {
        available.filter { !settings.cleanupSteps.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Cleanup steps", back: back)
            PageNote(text: "Voz runs these steps in order on each dictation. Extensions can add steps.")
            PanelGroup {
                ForEach(settings.cleanupSteps + off, id: \.self) { step in
                    row(step) {
                        if let index = settings.cleanupSteps.firstIndex(of: step) {
                            IconButton(icon: .chevronUp, help: "Move up") { move(index, by: -1) }
                                .disabled(index == 0)
                            IconButton(icon: .chevronDown, help: "Move down") { move(index, by: 1) }
                                .disabled(index == settings.cleanupSteps.count - 1)
                        }
                    }
                }
            }
            .animation(Theme.Motion.reorder, value: settings.cleanupSteps)
            HStack {
                Spacer(minLength: 0)
                Button("Reset to default") { settings.cleanupSteps = CleanupStep.standard }
                    .buttonStyle(.pill(.quiet, .small))
                    .disabled(settings.cleanupSteps == CleanupStep.standard)
            }
        }
    }

    private func row(_ step: String, @ViewBuilder controls: () -> some View) -> some View {
        PanelRow(title: name(of: step), detail: detail(of: step)) {
            HStack(spacing: 4) {
                controls()
                Toggle(name(of: step), isOn: settings.cleanupStepEnabled(step)).labelsHidden()
            }
        }
    }

    private func name(of step: String) -> String {
        CleanupStep(rawValue: step)?.name ?? catalog.cleanupSteps.first { $0.id == step }?.name ?? step
    }

    private func detail(of step: String) -> String? {
        if CleanupStep(rawValue: step) != nil { return nil }
        return catalog.cleanupSteps.contains { $0.id == step } ? "Extension" : "Extension not loaded"
    }

    private func move(_ index: Int, by offset: Int) {
        var steps = settings.cleanupSteps
        steps.swapAt(index, index + offset)
        settings.cleanupSteps = steps
    }
}

extension AppSettings {
    func cleanupStepEnabled(_ step: String) -> Binding<Bool> {
        Binding {
            self.cleanupSteps.contains(step)
        } set: { on in
            self.cleanupSteps = on ? self.cleanupSteps + [step] : self.cleanupSteps.filter { $0 != step }
        }
    }
}

struct CleanupPromptPage: View {
    @ObservedObject var settings: AppSettings
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Cleanup prompt", back: back)
            PageNote(text: "Voz cleans up each dictation with this prompt, on your Mac. Your dictionary words go at the end.")
            TextEditor(text: $settings.cleanupPrompt)
                .font(.ui(12))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 320)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hairline))
            HStack {
                Spacer(minLength: 0)
                Button("Reset to default") { settings.cleanupPrompt = CleanupPrompt.standard }
                    .buttonStyle(.pill(.quiet, .small))
                    .disabled(settings.cleanupPrompt == CleanupPrompt.standard)
            }
        }
    }
}
