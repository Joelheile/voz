import AppKit
import SwiftUI

struct ExtensionsPage: View {
    @ObservedObject var model: ExtensionsModel
    @ObservedObject var catalog: ExtensionCatalog
    let back: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Extensions", back: back)
            SearchField(text: $model.query, prompt: "Search extensions", focused: $searchFocused)
            if let message = model.message {
                Text(message)
                    .font(.ui(12))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let removed = model.removed { undoBar(removed) }
            CappedScrollView(maxHeight: 420) {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.installedRows.isEmpty { installed }
                    browse
                    yourOwn
                }
                .animation(Theme.Motion.section, value: model.expanded)
                .animation(Theme.Motion.section, value: model.confirming)
            }
        }
        .controlSize(.small)
        .onExitCommand { model.confirming = nil }
        .onAppear { if model.confirming == nil { searchFocused = true } }
        .task { await model.load() }
    }

    private var installed: some View {
        PanelGroup(title: "Installed") {
            ForEach(model.installedRows, id: \.name) { item in
                VStack(alignment: .leading, spacing: 0) {
                    PanelRow(title: item.name, detail: detail(for: item)) { installedControls(item) }
                    if model.expanded == item.name {
                        ExtensionDetails(item: item, model: model, catalog: catalog)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private func installedControls(_ item: InstalledExtension) -> some View {
        HStack(spacing: 8) {
            if let stage = model.stage(for: item.name) {
                StageLabel(text: stage.label)
            } else if model.latestVersion(for: item) != nil {
                Button("Update") { Task { await model.update(item) } }
                    .buttonStyle(.pill(.quiet, height: 26))
                    .disabled(model.working != nil)
            }
            IconButton(symbol: model.expanded == item.name ? "chevron.up" : "chevron.down", help: "Details") {
                model.toggleExpanded(item.name)
            }
            Toggle(item.name, isOn: Binding { model.isEnabled(item.name) } set: { model.setEnabled(item.name, $0) })
                .labelsHidden()
        }
        .transition(.blurReplace)
        .animation(Theme.Motion.section, value: model.stage(for: item.name))
    }

    private func detail(for item: InstalledExtension) -> String? {
        if !model.isEnabled(item.name) { return "Off" }
        if catalog.error(for: item.name) != nil { return "Could not load" }
        if needsSetup(item.name) { return "Needs setup" }
        if let latest = model.latestVersion(for: item) { return "Version \(latest) is out" }
        return model.summary(for: item.source) ?? item.source?.description ?? "In your extensions folder"
    }

    private func needsSetup(_ name: String) -> Bool {
        catalog.settings(for: name).contains { group in
            let config = model.config(for: group.extension)
            return group.fields.contains { $0.needsValue(in: config) }
        }
    }

    private func undoBar(_ source: PackageSource) -> some View {
        HStack {
            Text("Removed \(source.name)").font(.ui(12)).foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 0)
            Button("Undo") { Task { await model.undoRemove() } }
                .buttonStyle(.pill(.quiet, height: 24))
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var browse: some View {
        if model.loading {
            HStack {
                Spacer(minLength: 0)
                ProgressView()
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
        } else if !model.browseRows.isEmpty {
            PanelGroup(title: "Browse") {
                ForEach(model.browseRows) { listing in
                    VStack(alignment: .leading, spacing: 0) {
                        PanelRow(title: listing.name, detail: listing.summary) { control(for: listing) }
                        if model.confirming == listing.name {
                            confirmation(for: listing).transition(.opacity)
                        }
                    }
                }
            }
        } else if model.message == nil {
            Text(model.query.isEmpty ? "Nothing published yet" : "No matches")
                .font(.meta)
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    private var yourOwn: some View {
        PanelGroup(title: "Your own") {
            if model.commandInstalled {
                PanelRow(title: "New extension", detail: "Run voz new in Terminal") {
                    Button("Open folder", action: model.openExtensionsFolder).buttonStyle(.pill(.quiet, height: 26))
                }
            } else {
                PanelRow(title: "New extension", detail: "Adds the voz command to Terminal") {
                    Button("Install", action: model.installCommand).buttonStyle(.pill(.quiet, height: 26))
                }
            }
        }
    }

    @ViewBuilder
    private func control(for listing: PackageListing) -> some View {
        Group {
            if let stage = model.stage(for: listing.name) {
                StageLabel(text: stage.label)
            } else if model.confirming == listing.name {
                Button("Install") { Task { await model.install(listing) } }
                    .buttonStyle(.pill(.accent, height: 26))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.working != nil)
            } else {
                Button("Get") { model.confirming = listing.name }
                    .buttonStyle(.pill(.quiet, height: 26))
                    .disabled(model.working != nil)
            }
        }
        .transition(.blurReplace)
        .animation(Theme.Motion.section, value: model.stage(for: listing.name))
        .animation(Theme.Motion.section, value: model.confirming)
    }

    private func confirmation(for listing: PackageListing) -> some View {
        HStack(spacing: 4) {
            Text("By \(listing.publisher). Can read your transcripts and files.")
            if let page = listing.page { Link("Source", destination: page) }
        }
        .font(.ui(11.5))
        .foregroundStyle(Theme.inkTertiary)
        .padding(.bottom, 10)
    }
}

private struct StageLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text).font(.ui(12)).foregroundStyle(Theme.inkSecondary)
        }
        .frame(height: 26)
    }
}

private struct ExtensionDetails: View {
    let item: InstalledExtension
    @ObservedObject var model: ExtensionsModel
    @ObservedObject var catalog: ExtensionCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = catalog.error(for: item.name) {
                errorView(error)
            } else if model.isEnabled(item.name) && !catalog.isLoaded(item.name) {
                StageLabel(text: "Loading")
            } else {
                added
            }
            ForEach(catalog.settings(for: item.name), id: \.extension) { group in
                ExtensionSettingsForm(fields: group.fields, config: model.config(for: group.extension)) { value, key in
                    model.setConfig(value, key: key, for: group.extension)
                }
            }
            footer
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var added: some View {
        let commands = catalog.commands(for: item.name)
        let actions = catalog.actions(for: item.name)
        if !commands.isEmpty || !actions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(commands, id: \.self) { command in
                    line("Say \u{201C}\(command.phrase)\u{201D}")
                }
                ForEach(actions, id: \.self) { action in
                    HStack {
                        line(action.name)
                        Spacer(minLength: 0)
                        if let hotkey = action.hotkey.flatMap({ try? KeyChord(parsing: $0).label }) {
                            Text(hotkey).font(.ui(12)).foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(error)
                .font(.ui(11.5))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button("Copy error") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(item.name) failed to load in Voz: \(error)", forType: .string)
            }
            .buttonStyle(.pill(.quiet, height: 24))
        }
    }

    private var footer: some View {
        HStack {
            if let version = item.version { note("Version \(version)") }
            Spacer(minLength: 0)
            if item.source != nil {
                Button("Remove") { Task { await model.remove(item) } }
                    .buttonStyle(.pill(.quiet, height: 24))
                    .disabled(model.working != nil)
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.ui(12)).foregroundStyle(Theme.ink)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.ui(11.5)).foregroundStyle(Theme.inkTertiary)
    }
}

struct ExtensionSettingsForm: View {
    let fields: [SettingField]
    let config: [String: SettingValue]
    let save: (SettingValue, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fields, id: \.key) { field in
                PanelRow(title: field.title, detail: field.description) {
                    SettingControl(field: field, value: field.value(in: config)) { save($0, field.key) }
                }
            }
        }
        .padding(.leading, 12)
        .padding(.bottom, 6)
    }
}

private struct SettingControl: View {
    private static let fieldWidth: CGFloat = 140

    let field: SettingField
    let value: SettingValue
    let save: (SettingValue) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        switch (field.type, field.options) {
        case (.boolean, _):
            Toggle(field.title, isOn: Binding { value == .boolean(true) } set: { save(.boolean($0)) })
                .labelsHidden()
        case (.string, let options?):
            Picker(field.title, selection: Binding { value.text } set: { save(.string($0)) }) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        default:
            entry
        }
    }

    private var entry: some View {
        Group {
            if field.secret == true {
                SecureField(field.title, text: $text)
            } else {
                TextField(field.title, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.ui(12.5))
        .foregroundStyle(Theme.ink)
        .focused($focused)
        .onSubmit(commit)
        .onChange(of: focused) { if !focused { commit() } }
        .onAppear { text = value.text }
        .padding(.horizontal, 10)
        .frame(width: Self.fieldWidth, height: 26)
        .background(Theme.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    private func commit() {
        let entered = field.type == .number ? Double(text).map(SettingValue.number) : .string(text)
        guard let entered else { return text = value.text }
        if entered != value { save(entered) }
    }
}
