import AppKit
import SwiftUI

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
