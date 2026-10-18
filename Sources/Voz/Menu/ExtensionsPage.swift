import AppKit
import SwiftUI
import VozCore

@MainActor
final class ExtensionsModel: ObservableObject {
    private static let search = URL(string: "https://registry.npmjs.org/-/v1/search?text=keywords:voz-package&size=250")!
    private let home: VozHome
    private let fetch: @Sendable () async throws -> Data

    init(home: VozHome = VozHome(), fetch: @escaping @Sendable () async throws -> Data = { try await URLSession.shared.data(from: search).0 }) {
        self.home = home
        self.fetch = fetch
    }

    @Published var query = ""
    @Published var order = PackageOrder.popular
    @Published private(set) var listings: [PackageListing] = []
    @Published private(set) var installed: [PackageSource] = []
    @Published private(set) var loading = true
    @Published private(set) var working: String?
    @Published private(set) var message: String?
    @Published private(set) var commandInstalled = CommandLineTool.isInstalled

    var installedRows: [PackageSource] {
        installed.filter { matches($0.name, listing(named: $0.name)?.summary) }
    }

    var browseRows: [PackageListing] {
        let names = Set(installed.map(\.name))
        return listings.filter { !names.contains($0.name) && matches($0.name, $0.summary) }.ordered(by: order)
    }

    func listing(named name: String) -> PackageListing? {
        listings.first { $0.name == name }
    }

    func load() async {
        refreshInstalled()
        defer { loading = false }
        do {
            listings = try PackageListing.decodeSearch(try await fetch())
            message = nil
        } catch {
            message = "Could not reach npm. Check your connection."
        }
    }

    func install(_ listing: PackageListing) async {
        await run(listing.name) { try await PackageCLI.install("npm:\(listing.name)") }
    }

    func remove(_ source: PackageSource) async {
        await run(source.name) { try PackageCLI.remove(source.name) }
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

    private func run(_ name: String, _ operation: @escaping @Sendable () async throws -> Void) async {
        working = name
        do {
            try await Task.detached(operation: operation).value
            message = nil
        } catch {
            message = "\(error)"
        }
        working = nil
        refreshInstalled()
    }

    private func matches(_ name: String, _ summary: String?) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(needle) || summary?.localizedCaseInsensitiveContains(needle) == true
    }

    private func refreshInstalled() {
        let sources = (try? home.packageSources()) ?? []
        installed = sources.compactMap { try? PackageSource(parsing: $0, relativeTo: home.root) }
    }
}

struct ExtensionsPage: View {
    @ObservedObject var model: ExtensionsModel
    let back: () -> Void
    @State private var confirming: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Extensions", back: back)
            SearchField(text: $model.query, prompt: "Search extensions", focused: $searchFocused)
            Picker("Sort", selection: $model.order) {
                ForEach(PackageOrder.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let message = model.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            CappedScrollView(maxHeight: 420) {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.installedRows.isEmpty { installed }
                    browse
                    yourOwn
                }
            }
        }
        .controlSize(.small)
        .onAppear { searchFocused = true }
        .task { await model.load() }
    }

    private var installed: some View {
        PanelGroup(title: "Installed") {
            ForEach(model.installedRows, id: \.description) { source in
                PanelRow(title: source.name, detail: model.listing(named: source.name)?.summary ?? source.description) {
                    if model.working == source.name {
                        ProgressView()
                    } else {
                        Button("Remove") { Task { await model.remove(source) } }
                            .buttonStyle(.pill(.quiet, height: 26))
                            .disabled(model.working != nil)
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
            PanelGroup(title: "Browse") {
                ForEach(model.browseRows) { listing in
                    VStack(alignment: .leading, spacing: 0) {
                        ListingRow(listing: listing) { control(for: listing) }
                        if confirming == listing.name { confirmation(for: listing) }
                    }
                }
            }
        } else if model.message == nil {
            Text(model.query.isEmpty ? "No extensions published yet." : "No extensions match \"\(model.query)\".")
                .font(.meta)
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    private var yourOwn: some View {
        PanelGroup(title: "Your own") {
            PanelRow(title: "Extensions folder", detail: "Drop a .ts file here and voz loads it") {
                Button("Open", action: model.openExtensionsFolder).buttonStyle(.pill(.quiet, height: 26))
            }
            PanelRow(title: "voz command", detail: model.commandInstalled ? "Run voz install <package> in Terminal" : "Install packages from Terminal") {
                if !model.commandInstalled {
                    Button("Install", action: model.installCommand).buttonStyle(.pill(.quiet, height: 26))
                }
            }
        }
    }

    @ViewBuilder
    private func control(for listing: PackageListing) -> some View {
        if model.working == listing.name {
            ProgressView()
        } else if confirming != listing.name {
            Button("Install") { confirming = listing.name }
                .buttonStyle(.pill(.quiet, height: 26))
                .disabled(model.working != nil)
        }
    }

    private func confirmation(for listing: PackageListing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(listing.name) by \(listing.publisher) can read your transcripts, your files and the network. Read its source before you install it.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let page = listing.page { Link("Read source", destination: page).font(.system(size: 12)) }
                Spacer(minLength: 0)
                Button("Cancel") { confirming = nil }
                    .buttonStyle(.pill(.quiet, height: 26))
                Button("Install") {
                    confirming = nil
                    Task { await model.install(listing) }
                }
                .buttonStyle(.pill(.accent, height: 26))
            }
        }
        .padding(.bottom, 10)
    }
}

private struct ListingRow<Control: View>: View {
    let listing: PackageListing
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                if let summary = listing.summary {
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                Text("by \(listing.publisher), \(listing.monthlyDownloads.formatted(.number.notation(.compactName))) a month")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkTertiary)
            }
            Spacer(minLength: 0)
            control
        }
        .frame(minHeight: 40)
        .padding(.vertical, 6)
    }
}
