import SwiftUI

struct CleanupPage: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var catalog: ExtensionCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Cleanup", back: model.goBack)
            PanelGroup {
                PanelRow(title: "Clean up text", detail: "Removes filler words, fixes punctuation") {
                    Toggle("Clean up text", isOn: $settings.cleanupEnabled).labelsHidden()
                }
                if settings.cleanupEnabled {
                    if !catalog.cleanupModels.isEmpty || settings.cleanupModel != CleanupModelID.apple {
                        ModelPicker(title: "Model", selection: $settings.cleanupModel, options: [ModelOption(id: CleanupModelID.apple, name: "Apple", detail: "On device")] + ModelOption.extensions(catalog.cleanupModels))
                    }
                    LinkRow(title: "Steps", value: edited(settings.cleanupSteps != CleanupStep.standard)) { model.page = .cleanupSteps }
                    LinkRow(title: "Prompt", value: edited(settings.cleanupPrompt != CleanupPrompt.standard)) { model.page = .cleanupPrompt }
                }
                if let error = settings.pipelineError {
                    PanelRow(title: "Could not read settings.json", detail: error) { EmptyView() }
                }
            }
            .animation(Theme.Motion.section, value: settings.cleanupEnabled)
        }
    }

    private func edited(_ isEdited: Bool) -> String {
        isEdited ? "Edited" : "Default"
    }
}

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
            PageBar(title: "Cleanup steps", back: back) {
                ResetButton(visible: settings.cleanupSteps != CleanupStep.standard) { settings.cleanupSteps = CleanupStep.standard }
            }
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
            PageBar(title: "Cleanup prompt", back: back) {
                ResetButton(visible: settings.cleanupPrompt != CleanupPrompt.standard) { settings.cleanupPrompt = CleanupPrompt.standard }
            }
            PageNote(text: "Voz cleans up each dictation with this prompt, on your Mac. Your dictionary words go at the end.")
            TextEditor(text: $settings.cleanupPrompt)
                .font(.ui(12))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 320)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hairline))
        }
    }
}

private struct ResetButton: View {
    let visible: Bool
    let reset: () -> Void

    var body: some View {
        ZStack {
            if visible {
                Button("Reset", action: reset)
                    .buttonStyle(.pill(.quiet, .small))
                    .help("Go back to the default")
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.hover, value: visible)
    }
}
