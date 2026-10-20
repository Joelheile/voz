import Foundation

public struct VozHome: Sendable {
    public static let changedNotification = Notification.Name("com.joelheile.voz.extensions-changed")

    public let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".voz", isDirectory: true)) {
        self.root = root
    }

    public var extensions: URL { root.appendingPathComponent("extensions", isDirectory: true) }
    public var packages: URL { root.appendingPathComponent("packages", isDirectory: true) }
    public var settings: URL { root.appendingPathComponent("settings.json") }

    public var hasExtensions: Bool {
        let loose = (try? FileManager.default.contentsOfDirectory(atPath: extensions.path))?.contains { !$0.hasPrefix(".") } ?? false
        return loose || !((try? packageSources()) ?? []).isEmpty
    }

    public func writeAuthoringFiles(from resources: URL) throws {
        try FileManager.default.createDirectory(at: extensions, withIntermediateDirectories: true)
        try Self.writeTypes(into: root, from: resources)
        try Self.replace(root.appendingPathComponent("AGENTS.md"), with: resources.appendingPathComponent("AGENTS.md"))
    }

    public static func writeTypes(into folder: URL, from resources: URL) throws {
        let types = folder.appendingPathComponent("node_modules/voz", isDirectory: true)
        try FileManager.default.createDirectory(at: types, withIntermediateDirectories: true)
        try replace(types.appendingPathComponent("index.d.ts"), with: resources.appendingPathComponent("voz.d.ts"))
        try Data(#"{"name":"voz","private":true,"types":"index.d.ts"}"#.utf8).write(to: types.appendingPathComponent("package.json"))
    }

    public func packageSources() throws -> [String] {
        try readSettings()["packages"] as? [String] ?? []
    }

    public func setPackageSources(_ sources: [String]) throws {
        var settings = try readSettings()
        settings["packages"] = sources
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: self.settings, options: .atomic)
    }

    public func packageDirectories() throws -> [URL] {
        try packageSources().map { try PackageSource(parsing: $0, relativeTo: root).directory(in: self) }
    }

    public func localPackageDirectories() throws -> [URL] {
        try packageSources().compactMap {
            guard case .local(let url) = try PackageSource(parsing: $0, relativeTo: root) else { return nil }
            return url
        }
    }

    private static func replace(_ destination: URL, with source: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settings.path) else { return [:] }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any] ?? [:]
    }
}
