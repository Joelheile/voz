import AppKit
import LucideSwift
import SwiftUI

@MainActor
final class ExtensionsModel: ObservableObject {
    enum Tab: String, CaseIterable {
        case installed = "Installed", browse = "Browse"
    }

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
    nonisolated static let buildPrompt = """
    Build a Voz extension with me. Voz is my Mac dictation app, and extensions are TypeScript that it runs with Bun.

    Use the voz-extension skill. If you don't have it, run voz guide and follow what it prints. Read Voz's current state first, then interview me about what I want before you write any code.
    """
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
        tab = installed.isEmpty ? .browse : .installed
    }

    @Published var query = ""
    /// Listings whose latest package.json asks to read the screen, so Browse can say so before you install
    @Published private(set) var screenReaders: Set<String> = []
    @Published var tab = Tab.installed
    @Published var selected: String?
    @Published private(set) var listings: [PackageListing]
    @Published private(set) var installed: [InstalledExtension] = []
    @Published private(set) var disabled: [String] = []
    @Published private(set) var loading: Bool
    @Published private(set) var working: (name: String, stage: Stage)?
    @Published private(set) var removed: PackageSource?
    @Published private(set) var message: String?

    var installedRows: [InstalledExtension] {
        installed.filter { matches($0.name, summary(for: $0)) }
    }

    var browseRows: [PackageListing] {
        let installedFromNpm = Set(installed.compactMap { $0.source.flatMap(Self.npmName(of:)) })
        return listings.filter { !installedFromNpm.contains($0.name) && matches($0.name, $0.summary, $0.publisher) }.ordered(by: .popular)
    }

    var selectedInstalled: InstalledExtension? {
        installed.first { $0.name == selected }
    }

    var selectedListing: PackageListing? {
        listings.first { $0.name == selected }
    }

    var updateCount: Int {
        installed.filter { latestVersion(for: $0) != nil }.count
    }

    func summary(for item: InstalledExtension) -> String? {
        item.description ?? listing(for: item.source)?.summary
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
            let pending = listings.filter { listing in listing.name == selected && !found.contains { $0.name == listing.name } }
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
        query = ""
        if installed.contains(where: { $0.name == name }) {
            tab = .installed
            selected = name
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
        tab = .browse
        selected = name
    }

    func checkScreen(_ name: String) async {
        let url = URL(string: "https://registry.npmjs.org/\(name.replacingOccurrences(of: "/", with: "%2F"))/latest")!
        guard let data = try? await fetch(url), PackageListing.readsScreen(data) else { return }
        screenReaders.insert(name)
    }

    func install(_ listing: PackageListing) async {
        await install(.npm(name: listing.name, spec: listing.name), name: listing.name)
        if installed.contains(where: { $0.name == listing.name }) { tab = .installed }
    }

    func update(_ item: InstalledExtension) async {
        guard let source = item.source else { return }
        await run(item.name, .updating, change: .update, source: source) { _ in try await Packages.update(source) }
    }

    func remove(_ item: InstalledExtension) async {
        guard let source = item.source else { return }
        await run(item.name, .removing, change: .remove, source: source) { _ in try await Packages.remove(source.name) }
        guard message == nil else { return }
        selected = nil
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
            Log.app.error("Could not read extension settings: \(String(describing: error), privacy: .private)")
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

    func openExtensionsFolder() {
        do {
            try home.writeAuthoringFiles(from: ExtensionService.resources)
            NSWorkspace.shared.open(home.extensions)
        } catch {
            message = "Could not create \(home.extensions.path): \(error.localizedDescription)"
        }
    }

    func copyBuildPrompt() -> Bool {
        do {
            try CommandLineTool.install()
            try VozHome.writeSkill(into: FileManager.default.homeDirectoryForCurrentUser, from: ExtensionService.resources)
        } catch CommandLineToolError.cancelled {
            message = nil
            return false
        } catch {
            message = "\(error)"
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.buildPrompt, forType: .string)
        message = nil
        return true
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
            _ = try await Packages.install(source.description)
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

    nonisolated static func historyIcon(for source: String, in installed: [InstalledExtension]) -> LucideIconName {
        let package = installed.first { source == $0.name || source.hasPrefix("\($0.name)/") }
        return package?.icon.flatMap(lucideIcon(named:)) ?? .puzzle
    }

    private nonisolated static func lucideIcon(named kebabName: String) -> LucideIconName? {
        let words = kebabName.split(separator: "-")
        let camelName = words.prefix(1).joined() + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return LucideIconName(rawValue: camelName)
    }

    nonisolated static func displayName(_ name: String) -> String {
        let base = name.split(separator: "/").last.map(String.init) ?? name
        let words = (base.hasPrefix("voz-") ? String(base.dropFirst(4)) : base).split(separator: "-")
        return words.map { word in
            word.contains(where: "aeiouy".contains) ? word.prefix(1).uppercased() + word.dropFirst() : word.uppercased()
        }.joined(separator: " ")
    }

    private static func npmName(of source: PackageSource) -> String? {
        guard case .npm(let name, _) = source else { return nil }
        return name
    }
}
