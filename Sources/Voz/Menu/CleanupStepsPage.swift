import SwiftUI
import VozCore

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
            Text("Voz runs these steps in order on each dictation. Extensions can add steps.")
                .font(.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
                    .buttonStyle(.pill(.quiet, height: 28))
                    .disabled(settings.cleanupSteps == CleanupStep.standard)
            }
        }
    }

    private func row(_ step: String, @ViewBuilder controls: () -> some View) -> some View {
        PanelRow(title: name(of: step), detail: detail(of: step)) {
            HStack(spacing: 4) {
                controls()
                Toggle(name(of: step), isOn: enabled(step)).labelsHidden()
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

    private func enabled(_ step: String) -> Binding<Bool> {
        Binding {
            settings.cleanupSteps.contains(step)
        } set: { on in
            settings.cleanupSteps = on ? settings.cleanupSteps + [step] : settings.cleanupSteps.filter { $0 != step }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        var steps = settings.cleanupSteps
        steps.swapAt(index, index + offset)
        settings.cleanupSteps = steps
    }
}
