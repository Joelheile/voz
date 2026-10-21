import Foundation

public enum VozHomeError: Error, CustomStringConvertible {
    case malformedSettings(URL)
    case malformedPipeline(URL)

    public var description: String {
        switch self {
        case .malformedSettings(let url): "\(url.path) must be a JSON object with \"packages\" and \"disabled\" as lists of strings"
        case .malformedPipeline(let url): "\(url.path) must have \"speechModel\" and \"cleanupModel\" as strings and \"cleanupSteps\" as a list of strings"
        }
    }
}

private enum PipelineKey {
    static let speechModel = "speechModel"
    static let cleanupModel = "cleanupModel"
    static let cleanupSteps = "cleanupSteps"
    static let all = [speechModel, cleanupModel, cleanupSteps]
}

public struct InstalledExtension: Equatable, Sendable {
    public let name: String
    public let source: PackageSource?
}

public struct VozHome: Sendable {
    public static let changedNotification = Notification.Name("com.joelheile.voz.extensions-changed")

    public let root: URL
    private static let disabledKey = "disabled"

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".voz", isDirectory: true)) {
        self.root = root
    }

    public var extensions: URL { root.appendingPathComponent("extensions", isDirectory: true) }
    public var packages: URL { root.appendingPathComponent("packages", isDirectory: true) }
    public var settings: URL { root.appendingPathComponent("settings.json") }

    public var hasEnabledExtensions: Bool {
        do {
            let disabled = try disabledExtensions()
            return try installedExtensions().contains { !disabled.contains($0.name) }
        } catch {
            return true
        }
    }

    public func installedExtensions() throws -> [InstalledExtension] {
        let packages = try packageSources().map { raw in
            let source = try PackageSource(parsing: raw, relativeTo: root)
            return InstalledExtension(name: Self.packageName(in: source.directory(in: self)), source: source)
        }
        return looseExtensionNames().map { InstalledExtension(name: $0, source: nil) } + packages
    }

    private func looseExtensionNames() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: extensions, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return files.filter { !$0.lastPathComponent.hasPrefix(".") }.compactMap { file in
            let isFolder = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isFolder {
                let hasEntry = ["index.ts", "index.js"].contains { FileManager.default.fileExists(atPath: file.appendingPathComponent($0).path) }
                return hasEntry ? file.lastPathComponent : nil
            }
            return ["ts", "js"].contains(file.pathExtension) ? file.deletingPathExtension().lastPathComponent : nil
        }
        .sorted()
    }

    private static func packageName(in directory: URL) -> String {
        let manifest = (try? Data(contentsOf: directory.appendingPathComponent("package.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return manifest?["name"] as? String ?? directory.lastPathComponent
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
        let packages = try readSettings()["packages"]
        guard let packages else { return [] }
        guard let list = packages as? [String] else { throw VozHomeError.malformedSettings(settings) }
        return list
    }

    public func setPackageSources(_ sources: [String]) throws {
        _ = try packageSources()
        var settings = try readSettings()
        settings["packages"] = sources
        try writeSettings(settings)
    }

    public func disabledExtensions() throws -> [String] {
        guard let disabled = try readSettings()[Self.disabledKey] else { return [] }
        guard let list = disabled as? [String] else { throw VozHomeError.malformedSettings(settings) }
        return list
    }

    public func setExtension(_ name: String, enabled: Bool) throws {
        let others = try disabledExtensions().filter { $0 != name }
        var settings = try readSettings()
        settings[Self.disabledKey] = enabled ? others : others + [name]
        try writeSettings(settings)
    }

    public func pipelineChoices() throws -> PipelineChoices {
        let settings = try readSettings()
        let standard = PipelineChoices.standard
        let speechModel = settings[PipelineKey.speechModel] ?? standard.speechModel
        let cleanupModel = settings[PipelineKey.cleanupModel] ?? standard.cleanupModel
        let cleanupSteps = settings[PipelineKey.cleanupSteps] ?? standard.cleanupSteps
        guard let speechModel = speechModel as? String, let cleanupModel = cleanupModel as? String, let cleanupSteps = cleanupSteps as? [String] else {
            throw VozHomeError.malformedPipeline(self.settings)
        }
        return PipelineChoices(speechModel: speechModel, cleanupModel: cleanupModel, cleanupSteps: cleanupSteps)
    }

    public func setPipelineChoices(_ choices: PipelineChoices) throws {
        _ = try pipelineChoices()
        var settings = try readSettings()
        settings[PipelineKey.speechModel] = choices.speechModel
        settings[PipelineKey.cleanupModel] = choices.cleanupModel
        settings[PipelineKey.cleanupSteps] = choices.cleanupSteps
        try writeSettings(settings)
    }

    public func extensionSettings() throws -> Data {
        let settings = try readSettings().filter { !PipelineKey.all.contains($0.key) }
        return try JSONSerialization.data(withJSONObject: settings, options: .sortedKeys)
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

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: self.settings, options: .atomic)
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settings.path) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any] else {
            throw VozHomeError.malformedSettings(settings)
        }
        return object
    }
}
