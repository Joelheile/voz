import AppKit
import LucideSwift
import SwiftUI

struct ExtensionsPage: View {
    @ObservedObject var model: ExtensionsModel
    @ObservedObject var catalog: ExtensionCatalog
    @ObservedObject var settings: AppSettings
    let toast: (String) -> Void
    let back: () -> Void

    var body: some View {
        Group {
            if let item = model.selectedInstalled {
                InstalledDetail(item: item, model: model, catalog: catalog, settings: settings)
                    .transition(.opacity)
            } else if let listing = model.selectedListing {
                ListingDetail(listing: listing, model: model)
                    .transition(.opacity)
            } else {
                ExtensionList(model: model, catalog: catalog, toast: toast, back: back)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.section, value: model.selected)
        .controlSize(.small)
        .task { await model.load() }
    }
}

private struct ExtensionList: View {
    @ObservedObject var model: ExtensionsModel
    @ObservedObject var catalog: ExtensionCatalog
    let toast: (String) -> Void
    let back: () -> Void
    @FocusState private var searchFocused: Bool
    @State private var copiedPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Extensions", back: back) {
                HStack(spacing: 4) {
                    IconButton(icon: .folderOpen, help: "Open extensions folder", action: model.openExtensionsFolder)
                    Button(action: copyBuildPrompt) {
                        ZStack {
                            crossfading("Build your own", visible: !copiedPrompt)
                            crossfading("Copied", visible: copiedPrompt)
                        }
                    }
                    .buttonStyle(.pill(.accent, .small))
                    .fixedSize()
                    .help("Copy a prompt that has your coding agent build an extension with you")
                }
            }
            SearchField(text: $model.query, prompt: "Search extensions", focused: $searchFocused)
            TabBar(tabs: ExtensionsModel.Tab.allCases, selection: $model.tab)
            MessageView(model: model)
            if let removed = model.removed { undoBar(removed) }
            CappedScrollView(maxHeight: 400) {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.tab {
                    case .installed: installed
                    case .browse: browse
                    }
                }
            }
        }
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private var installed: some View {
        if model.installedRows.isEmpty {
            empty(model.query.isEmpty ? "Nothing installed yet" : "No matches")
            if model.query.isEmpty {
                Button("Browse extensions") { model.tab = .browse }
                    .buttonStyle(.pill(.quiet, .small))
                    .padding(.leading, 8)
            }
        } else {
            VStack(spacing: 2) {
                ForEach(model.installedRows, id: \.name) { item in
                    if item.name != model.installedRows.first?.name { RowDivider().padding(.horizontal, 8) }
                    ExtensionRow(name: item.name, summary: model.summary(for: item), dimmed: !model.isEnabled(item.name), attention: attention(for: item), readsScreen: catalog.readsScreen(item.name)) {
                        model.selected = item.name
                    } trailing: {
                        Toggle(item.name, isOn: Binding { model.isEnabled(item.name) } set: { model.setEnabled(item.name, $0) })
                            .labelsHidden()
                    }
                }
            }
        }
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
            VStack(spacing: 2) {
                ForEach(model.browseRows) { listing in
                    if listing.id != model.browseRows.first?.id { RowDivider().padding(.horizontal, 8) }
                    ExtensionRow(name: listing.name, summary: listing.summary, publisher: listing.publisher, downloads: listing.monthlyDownloads) {
                        model.selected = listing.name
                    } trailing: {
                        if let stage = model.stage(for: listing.name) {
                            StageLabel(text: stage.label)
                        } else {
                            Button("Get") { model.selected = listing.name }
                                .buttonStyle(.pill(.quiet, .small))
                        }
                    }
                }
            }
        } else if model.message == nil {
            empty(model.query.isEmpty ? "Nothing published yet" : "No matches")
        }
    }

    private func attention(for item: InstalledExtension) -> String? {
        guard model.isEnabled(item.name) else { return nil }
        if catalog.error(for: item.name) != nil { return "Could not load" }
        if needsSetup(item.name) { return "Needs setup" }
        if model.latestVersion(for: item) != nil { return "Update" }
        return nil
    }

    private func needsSetup(_ name: String) -> Bool {
        catalog.settings(for: name).contains { group in
            let config = model.config(for: group.extension)
            return group.fields.contains { $0.needsValue(in: config) }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.meta)
            .foregroundStyle(Theme.inkTertiary)
            .padding(.leading, 10)
    }

    private func undoBar(_ source: PackageSource) -> some View {
        HStack {
            Text("Removed \(ExtensionsModel.displayName(source.name))").font(.ui(12)).foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 0)
            Button("Undo") { Task { await model.undoRemove() } }
                .buttonStyle(.pill(.quiet, .small))
                .disabled(model.working != nil)
        }
        .transition(.opacity)
    }

    private func copyBuildPrompt() {
        guard model.copyBuildPrompt() else { return }
        toast("Prompt copied. Paste it into Claude Code, Codex or any coding agent.")
        copiedPrompt = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            copiedPrompt = false
        }
    }

    private func crossfading(_ label: String, visible: Bool) -> some View {
        Text(label)
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 2)
    }
}

private struct ExtensionRow<Trailing: View>: View {
    let name: String
    let summary: String?
    var publisher: String?
    var downloads = 0
    var dimmed = false
    var attention: String?
    var readsScreen = false
    let open: () -> Void
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(ExtensionsModel.displayName(name)).font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                        if readsScreen { ScreenFlag() }
                        if let attention {
                            Text(attention).font(.ui(11, weight: .medium)).foregroundStyle(Theme.accent)
                        }
                    }
                    if let summary {
                        Text(summary)
                            .font(.meta)
                            .lineSpacing(2)
                            .lineLimit(2)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let publisher {
                        HStack(spacing: 10) {
                            Fact(icon: .user, text: publisher)
                            if downloads > 0 {
                                Fact(icon: .download, text: downloads.formatted(.number.notation(.compactName)))
                                    .help("\(downloads.formatted()) downloads in the last month")
                            }
                        }
                        .font(.ui(11))
                        .lineLimit(1)
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(dimmed ? 0.5 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(hovering ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
        .animation(Theme.Motion.section, value: dimmed)
    }
}

/// Marks extensions that read the window in front, wherever they are listed
private struct ScreenFlag: View {
    var body: some View {
        Icon(.eye, size: 12)
            .foregroundStyle(Theme.inkTertiary)
            .help("Reads your screen")
    }
}

private struct MessageView: View {
    @ObservedObject var model: ExtensionsModel

    var body: some View {
        if let message = model.message {
            Text(message)
                .font(.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct DetailHeader<Control: View>: View {
    let name: String
    let summary: String?
    let byline: String
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ExtensionsModel.displayName(name)).font(.display(15)).foregroundStyle(Theme.ink)
                    Text(byline).font(.meta).foregroundStyle(Theme.inkTertiary).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                control
            }
            if let summary {
                Text(summary)
                    .font(.ui(15))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ListingDetail: View {
    private static let trust = "Extensions run on your Mac with the same access as Voz, so they can read your transcripts and files. Install ones from people you trust."

    let listing: PackageListing
    @ObservedObject var model: ExtensionsModel
    @State private var showsTrust = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            MessageView(model: model)
            if model.screenReaders.contains(listing.name) {
                PanelGroup(title: "Before you install") {
                    PanelRow(title: "Reads your screen", detail: "The text of the window in front, without passwords or keys") { ScreenFlag() }
                }
                .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 10) {
                if let summary = listing.summary {
                    Text(summary)
                        .font(.ui(15))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                facts
            }
        }
        .padding(.bottom, 2)
        .animation(Theme.Motion.section, value: model.screenReaders.contains(listing.name))
        .task(id: listing.name) { await model.checkScreen(listing.name) }
        .onExitCommand { model.selected = nil }
    }

    private var header: some View {
        HStack(spacing: 4) {
            IconButton(icon: .chevronLeft, help: "Back to Browse") { model.selected = nil }
                .keyboardShortcut("[", modifiers: .command)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ExtensionsModel.displayName(listing.name))
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(listing.version)
                    .font(.meta)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkTertiary)
                    .textSelection(.enabled)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            IconButton(icon: .info, help: Self.trust) { showsTrust.toggle() }
                .popover(isPresented: $showsTrust, arrowEdge: .bottom) {
                    PageNote(text: Self.trust)
                        .frame(width: 240)
                        .padding(12)
                }
            install
                .padding(.leading, 4)
        }
        .padding(.leading, -6)
    }

    private var install: some View {
        Group {
            if let stage = model.stage(for: listing.name) {
                StageLabel(text: stage.label)
            } else {
                Button("Install") { Task { await model.install(listing) } }
                    .buttonStyle(.pill(.accent, .small))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.working != nil)
            }
        }
        .transition(.blurReplace)
        .animation(Theme.Motion.section, value: model.stage(for: listing.name))
    }

    private var facts: some View {
        HStack(spacing: 12) {
            Fact(icon: .user, text: listing.publisher)
            if listing.monthlyDownloads > 0 {
                Fact(icon: .download, text: "\(listing.monthlyDownloads.formatted(.number.notation(.compactName)))/mo")
                    .help("\(listing.monthlyDownloads.formatted()) downloads in the last month")
            }
            if let published = listing.published {
                Fact(icon: .clock, text: published.formatted(.relative(presentation: .named)))
                    .help("Updated \(published.formatted(date: .abbreviated, time: .omitted))")
            }
            Spacer(minLength: 0)
            if let page = listing.page {
                Link(destination: page) {
                    HStack(spacing: 2) {
                        Text("npm")
                        Icon(.arrowUpRight, size: 12)
                    }
                }
                    .help("Open the package page")
            }
        }
        .font(.meta)
        .lineLimit(1)
        .foregroundStyle(Theme.inkTertiary)
    }
}

private struct Fact: View {
    let icon: LucideIconName
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Icon(icon, size: 12)
            Text(text).monospacedDigit()
        }
    }
}

private struct InstalledDetail: View {
    let item: InstalledExtension
    @ObservedObject var model: ExtensionsModel
    @ObservedObject var catalog: ExtensionCatalog
    @ObservedObject var settings: AppSettings

    private var enabled: Bool { model.isEnabled(item.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageBar(title: "Installed") { model.selected = nil }
            CappedScrollView(maxHeight: 460) {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(name: item.name, summary: model.summary(for: item), byline: byline) {
                        Toggle(item.name, isOn: Binding { enabled } set: { model.setEnabled(item.name, $0) })
                            .labelsHidden()
                            .help(enabled ? "Turn off" : "Turn on")
                    }
                    MessageView(model: model)
                    if let latest = model.latestVersion(for: item) { update(latest) }
                    if let error = catalog.error(for: item.name) {
                        errorView(error)
                    } else if !enabled {
                        note("Off. Voz does not run it until you turn it on.")
                    } else if !catalog.isLoaded(item.name) {
                        StageLabel(text: "Loading")
                    } else {
                        added
                    }
                    ForEach(catalog.settings(for: item.name), id: \.extension) { group in
                        let config = model.config(for: group.extension)
                        PanelGroup(title: "Settings") {
                            ForEach(group.fields, id: \.key) { field in
                                PanelRow(title: field.title, detail: field.description) {
                                    SettingControl(field: field, value: field.value(in: config)) { model.setConfig($0, key: field.key, for: group.extension) }
                                }
                            }
                        }
                    }
                    ForEach(catalog.lists(for: item.name), id: \.id) { list in
                        ExtensionListGroup(list: list, catalog: catalog)
                    }
                    footer
                }
            }
        }
        .onExitCommand { model.selected = nil }
    }

    private var byline: String {
        [item.version.map { "\(item.name) \($0)" } ?? item.name, item.source == nil ? "in your extensions folder" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func update(_ latest: String) -> some View {
        HStack {
            Text("Version \(latest) is out").font(.ui(12)).foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 0)
            Group {
                if let stage = model.stage(for: item.name) {
                    StageLabel(text: stage.label)
                } else {
                    Button("Update") { Task { await model.update(item) } }
                        .buttonStyle(.pill(.accent, .small))
                        .disabled(model.working != nil)
                }
            }
            .transition(.blurReplace)
            .animation(Theme.Motion.section, value: model.stage(for: item.name))
        }
    }

    @ViewBuilder
    private var added: some View {
        let commands = catalog.commands(for: item.name)
        let actions = catalog.actions(for: item.name)
        let steps = catalog.cleanupSteps(for: item.name)
        let readsScreen = catalog.readsScreen(item.name)
        if !commands.isEmpty || !actions.isEmpty || !steps.isEmpty || readsScreen {
            PanelGroup(title: "What it adds") {
                if readsScreen {
                    PanelRow(title: "Reads your screen", detail: "The text of the window in front, without passwords or keys") { ScreenFlag() }
                }
                ForEach(commands, id: \.self) { command in
                    PanelRow(title: "\u{201C}\(command.phrase)\u{201D}", detail: "Voice command") { EmptyView() }
                }
                ForEach(actions, id: \.self) { action in
                    PanelRow(title: action.name) {
                        if let hotkey = action.hotkeyLabel {
                            Text(hotkey).font(.ui(12)).foregroundStyle(Theme.inkTertiary)
                        }
                        Button("Run") { catalog.run(action) }
                            .buttonStyle(.pill(.accent, .small))
                    }
                }
                ForEach(steps, id: \.self) { step in
                    PanelRow(title: step.name, detail: "Cleanup step") {
                        Toggle(step.name, isOn: settings.cleanupStepEnabled(step.id)).labelsHidden()
                    }
                }
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(error)
                .font(.meta)
                .foregroundStyle(Theme.recording)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button("Copy error") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(item.name) failed to load in Voz: \(error)", forType: .string)
            }
            .buttonStyle(.pill(.quiet, .small))
        }
    }

    @ViewBuilder
    private var footer: some View {
        if item.source != nil {
            HStack {
                note("Remove deletes it from your Mac.")
                Spacer(minLength: 0)
                Group {
                    if model.stage(for: item.name) == .removing {
                        StageLabel(text: ExtensionsModel.Stage.removing.label)
                    } else {
                        Button("Remove") { Task { await model.remove(item) } }
                            .buttonStyle(.pill(.quiet, .small))
                            .disabled(model.working != nil)
                    }
                }
                .transition(.blurReplace)
                .animation(Theme.Motion.section, value: model.stage(for: item.name))
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.meta).foregroundStyle(Theme.inkTertiary).fixedSize(horizontal: false, vertical: true)
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

private struct SettingControl: View {
    private static let fieldWidth: CGFloat = 116

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
        case (.string, _) where field.folder == true:
            Button(action: chooseFolder) {
                HStack(spacing: 6) {
                    Icon(.folder, size: 13).foregroundStyle(Theme.inkSecondary)
                    Text(value.text.isEmpty ? "Choose" : URL(fileURLWithPath: value.text).lastPathComponent)
                        .font(.meta)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: Self.fieldWidth, alignment: .leading)
                .fieldBackground(.small)
            }
            .buttonStyle(.pressable(0.97))
            .help(value.text.isEmpty ? "Choose a folder" : value.text)
        default:
            entry
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = field.title
        if !value.text.isEmpty { panel.directoryURL = URL(fileURLWithPath: (value.text as NSString).expandingTildeInPath) }
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, url.path != value.text else { return }
        save(.string(url.path))
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
        .font(.meta)
        .foregroundStyle(Theme.ink)
        .focused($focused)
        .onSubmit(commit)
        .onChange(of: focused) { if !focused { commit() } }
        .onAppear { text = value.text }
        .frame(width: Self.fieldWidth)
        .fieldBackground(.small)
    }

    private func commit() {
        let entered = field.type == .number ? Double(text).map(SettingValue.number) : .string(text)
        guard let entered else { return text = value.text }
        if entered != value { save(entered) }
    }
}

/// A list an extension fills, such as what Reply learned about your writing. It loads when the page opens.
struct ExtensionListGroup: View {
    let list: SettingsList
    @ObservedObject var catalog: ExtensionCatalog
    @State private var items: [SettingsListItem]?
    @State private var error: String?

    var body: some View {
        PanelGroup(title: list.title) {
            if let items, !items.isEmpty {
                ForEach(items, id: \.self) { item in
                    PanelRow(title: item.title, detail: item.detail) {
                        if list.removable {
                            IconButton(icon: .x, help: "Remove") { load(removing: item.id) }
                        }
                    }
                }
            } else {
                PanelRow(title: status, detail: list.description.isEmpty ? nil : list.description) {}
            }
        }
        .animation(Theme.Motion.section, value: items)
        .task(id: list) { load() }
    }

    private var status: String {
        if let error { return error }
        return items == nil ? "Loading" : "Nothing yet"
    }

    private func load(removing remove: String? = nil) {
        Task {
            do {
                items = try await catalog.items(list, removing: remove)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
