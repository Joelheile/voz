import AppKit
import SwiftUI
import VozCore

@MainActor
final class ExtensionsModel: ObservableObject {
    enum Stage: Equatable {
        case gettingBun(Double), installing, updating, removing

        var label: String {
            switch self {
            case .gettingBun(let fraction): "Getting Bun \(fraction.formatted(.percent.precision(.fractionLength(0))))"
            case .installing: "Installing"
            case .updating: "Updating"
            case .removing: "Removing"
            }
        }
    }

    private static let search = URL(string: "https://registry.npmjs.org/-/v1/search?text=keywords:voz-package&size=250")!
    private static let undoWindow: Duration = .seconds(5)
    private let home: VozHome
    private let analytics: Analytics
    private let cache: URL?
    private let fetch: @Sendable (URL) async throws -> Data
    private var undoExpiry: Task<Void, Never>?

    init(
        analytics: Analytics,
        home: VozHome = VozHome(),
        cache: URL? = try? AppStorage.directory().appendingPathComponent("extension-listings.json"),
        fetch: @escaping @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }
    ) {
        self.home = home
        self.analytics = analytics
        self.cache = cache
        self.fetch = fetch
        let cached = cache.flatMap { try? JSONDecoder().decode([PackageListing].self, from: Data(contentsOf: $0)) } ?? []
        listings = cached
        loading = cached.isEmpty
        refreshInstalled()
    }

    @Published var query = ""
    @Published var confirming: String?
    @Published var expanded: String?
    @Published private(set) var listings: [PackageListing]
    @Published private(set) var installed: [InstalledExtension] = []
    @Published private(set) var disabled: [String] = []
    @Published private(set) var loading: Bool
    @Published private(set) var working: (name: String, stage: Stage)?
    @Published private(set) var removed: PackageSource?
    @Published private(set) var message: String?
    @Published private(set) var commandInstalled = CommandLineTool.isInstalled

    var installedRows: [InstalledExtension] {
        installed.filter { matches($0.name, summary(for: $0.source)) }
    }

    var browseRows: [PackageListing] {
        let installedFromNpm = Set(installed.compactMap { $0.source.flatMap(Self.npmName(of:)) })
        return listings.filter { !installedFromNpm.contains($0.name) && matches($0.name, $0.summary, $0.publisher) }.ordered(by: .popular)
    }

    var updateCount: Int {
        installed.filter { latestVersion(for: $0) != nil }.count
    }

    func summary(for source: PackageSource?) -> String? {
        listing(for: source)?.summary
    }

    func latestVersion(for item: InstalledExtension) -> String? {
        guard let source = item.source, !source.isPinned, let latest = listing(for: source)?.version, latest != item.version else { return nil }
        return latest
    }

    func stage(for name: String) -> Stage? {
        working?.name == name ? working?.stage : nil
    }

    func load() async {
        refreshInstalled()
        defer { loading = false }
        do {
            let data = try await fetch(Self.search)
            let found = try PackageListing.decodeSearch(data)
            let pending = listings.filter { listing in listing.name == confirming && !found.contains { $0.name == listing.name } }
            listings = found + pending
            message = nil
            if let cache { try? data.write(to: cache) }
        } catch is DecodingError {
            message = "Could not read the npm search results."
        } catch {
            if listings.isEmpty { message = "Could not reach npm. Check your connection." }
        }
    }

    func reveal(_ name: String) async {
        query = name
        if installed.contains(where: { $0.name == name }) {
            expanded = name
            return
        }
        if !listings.contains(where: { $0.name == name }) {
            do {
                let url = URL(string: "https://registry.npmjs.org/\(name.replacingOccurrences(of: "/", with: "%2F"))")!
                listings.append(try PackageListing.decodePackument(await fetch(url)))
            } catch {
                message = "Could not find \(name) on npm."
                return
            }
        }
        confirming = name
    }

    func install(_ listing: PackageListing) async {
        confirming = nil
        await install(.npm(name: listing.name, spec: listing.name), name: listing.name)
        expanded = listing.name
    }

    func update(_ item: InstalledExtension) async {
        guard let source = item.source else { return }
        await run(item.name, .updating, change: .update, source: source) { _ in try await PackageCLI.update(source) }
    }

    func remove(_ item: InstalledExtension) async {
        guard let source = item.source else { return }
        if expanded == item.name { expanded = nil }
        await run(item.name, .removing, change: .remove, source: source) { _ in try await PackageCLI.remove(source.name) }
        guard message == nil else { return }
        removed = source
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.removed = nil
        }
    }

    func undoRemove() async {
        guard let source = removed else { return }
        removed = nil
        undoExpiry?.cancel()
        await install(source, name: source.name)
    }

    func setEnabled(_ name: String, _ enabled: Bool) {
        do {
            try home.setExtension(name, enabled: enabled)
            disabled = try home.disabledExtensions()
            message = nil
        } catch {
            message = "\(error)"
        }
    }

    func config(for name: String) -> [String: SettingValue] {
        do {
            return try home.config(for: name)
        } catch {
            message = "\(error)"
            return [:]
        }
    }

    func setConfig(_ value: SettingValue, key: String, for name: String) {
        do {
            try home.setConfig(value, key: key, for: name)
            message = nil
        } catch {
            message = "\(error)"
        }
    }

    func isEnabled(_ name: String) -> Bool {
        !disabled.contains(name)
    }

    func toggleExpanded(_ name: String) {
        expanded = expanded == name ? nil : name
    }

    func openExtensionsFolder() {
        do {
            try home.writeAuthoringFiles(from: ExtensionService.resources)
            NSWorkspace.shared.open(home.extensions)
        } catch {
            message = "Could not create \(home.extensions.path): \(error.localizedDescription)"
        }
    }

    func installCommand() {
        do {
            try CommandLineTool.install()
            message = nil
        } catch {
            message = "\(error)"
        }
        commandInstalled = CommandLineTool.isInstalled
    }

    func matches(_ fields: String?...) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return fields.contains { $0?.localizedCaseInsensitiveContains(needle) == true }
    }

    private func install(_ source: PackageSource, name: String) async {
        let stage: Stage = BunRuntime.isInstalled ? .installing : .gettingBun(0)
        await run(name, stage, change: .install, source: source) { model in
            _ = try await BunRuntime.ensure { fraction in
                Task { @MainActor in model?.showBunProgress(fraction, for: name) }
            }
            await MainActor.run { model?.working = (name, .installing) }
            try await PackageCLI.install(source.description)
        }
    }

    private func showBunProgress(_ fraction: Double, for name: String) {
        let rounded = (fraction * 100).rounded() / 100
        guard working?.name == name, case .gettingBun(let shown)? = working?.stage, shown != rounded else { return }
        working = (name, .gettingBun(rounded))
    }

    private func run(
        _ name: String,
        _ stage: Stage,
        change: ExtensionChange,
        source: PackageSource,
        _ operation: @escaping @Sendable (ExtensionsModel?) async throws -> Void
    ) async {
        working = (name, stage)
        do {
            try await Task.detached { [weak self] in try await operation(self) }.value
            message = nil
            analytics.capture(.extensionChanged(change: change, source: source))
        } catch {
            message = "\(error)"
            let failure: ExtensionFailure = if case .gettingBun = working?.stage { .bunDownload } else { .packageCommand }
            analytics.capture(.extensionFailed(change: change, source: source, failure: failure))
        }
        working = nil
        refreshInstalled()
    }

    private func refreshInstalled() {
        do {
            installed = try home.installedExtensions()
            disabled = try home.disabledExtensions()
        } catch {
            installed = []
            disabled = []
            message = "\(error)"
        }
    }

    private func listing(for source: PackageSource?) -> PackageListing? {
        guard let name = source.flatMap(Self.npmName(of:)) else { return nil }
        return listings.first { $0.name == name }
    }

    private static func npmName(of source: PackageSource) -> String? {
        guard case .npm(let name, _) = source else { return nil }
        return name
    }
}

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
