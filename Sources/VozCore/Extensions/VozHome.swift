import Darwin
import Foundation

public enum VozHomeError: Error, CustomStringConvertible {
    case malformedSettings(URL)
    case malformedPipeline(URL)
    case malformedConfig(URL, String)

    public var description: String {
        switch self {
        case .malformedSettings(let url): "\(url.path) must be a JSON object with \"packages\" and \"disabled\" as lists of strings"
        case .malformedPipeline(let url): "\(url.path) must have \"speechModel\" and \"cleanupModel\" as strings and \"cleanupSteps\" as a list of strings"
        case .malformedConfig(let url, let name): "\(url.path) must have \"config.\(name)\" as an object"
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
    public var version: String? = nil
}

public struct VozHome: Sendable {
    public static let changedNotification = Notification.Name("com.joelheile.voz.extensions-changed")

    public let root: URL
    private static let disabledKey = "disabled"
    private static let configKey = "config"

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
            let directory = source.directory(in: self)
            let manifest = Self.manifest(in: directory)
            return InstalledExtension(name: manifest.name ?? directory.lastPathComponent, source: source, version: manifest.version)
        }
        return try looseExtensionNames().map { InstalledExtension(name: $0, source: nil) } + packages
    }

    private func looseExtensionNames() throws -> [String] {
        guard FileManager.default.fileExists(atPath: extensions.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: extensions, includingPropertiesForKeys: [.isDirectoryKey])
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

    private static func manifest(in directory: URL) -> (name: String?, version: String?) {
        let manifest = (try? Data(contentsOf: directory.appendingPathComponent("package.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return (manifest?["name"] as? String, manifest?["version"] as? String)
    }

    public func writeAuthoringFiles(from resources: URL) throws {
        try FileManager.default.createDirectory(at: extensions, withIntermediateDirectories: true)
        let types = root.appendingPathComponent("node_modules/voz", isDirectory: true)
        try FileManager.default.createDirectory(at: types, withIntermediateDirectories: true)
        try Self.replace(types.appendingPathComponent("index.d.ts"), with: resources.appendingPathComponent("voz.d.ts"))
        try Data(#"{"name":"voz","private":true,"types":"index.d.ts"}"#.utf8).write(to: types.appendingPathComponent("package.json"))
        try Self.replace(root.appendingPathComponent("AGENTS.md"), with: resources.appendingPathComponent("AGENTS.md"))
    }

    public static func writeTypes(into folder: URL, from resources: URL) throws {
        try replace(folder.appendingPathComponent("voz.d.ts"), with: resources.appendingPathComponent("voz.d.ts"))
    }

    public func packageSources() throws -> [String] {
        try packageSources(in: readSettings())
    }

    private func packageSources(in settings: [String: Any]) throws -> [String] {
        let packages = settings["packages"]
        guard let packages else { return [] }
        guard let list = packages as? [String] else { throw VozHomeError.malformedSettings(self.settings) }
        return list
    }

    public func setPackageSources(_ sources: [String]) throws {
        try updateSettings { settings in
            _ = try packageSources(in: settings)
            settings["packages"] = sources
        }
    }

    public func disabledExtensions() throws -> [String] {
        try disabledExtensions(in: readSettings())
    }

    private func disabledExtensions(in settings: [String: Any]) throws -> [String] {
        guard let disabled = settings[Self.disabledKey] else { return [] }
        guard let list = disabled as? [String] else { throw VozHomeError.malformedSettings(self.settings) }
        return list
    }

    public func setExtension(_ name: String, enabled: Bool) throws {
        try updateSettings { settings in
            let others = try disabledExtensions(in: settings).filter { $0 != name }
            settings[Self.disabledKey] = enabled ? others : others + [name]
        }
    }

    public func pipelineChoices() throws -> PipelineChoices {
        try pipelineChoices(in: readSettings())
    }

    private func pipelineChoices(in settings: [String: Any]) throws -> PipelineChoices {
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
        try updateSettings { settings in
            _ = try pipelineChoices(in: settings)
            settings[PipelineKey.speechModel] = choices.speechModel
            settings[PipelineKey.cleanupModel] = choices.cleanupModel
            settings[PipelineKey.cleanupSteps] = choices.cleanupSteps
        }
    }

    public func config(for name: String) throws -> [String: SettingValue] {
        try configObject(for: name).compactMapValues { value in
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else { return nil }
            return try? JSONDecoder().decode(SettingValue.self, from: data)
        }
    }

    public func setConfig(_ value: SettingValue, key: String, for name: String) throws {
        try updateSettings { settings in
            var object = try configObject(for: name, in: settings)
            switch value {
            case .string(let string): object[key] = string
            case .number(let number): object[key] = number
            case .boolean(let boolean): object[key] = boolean
            }
            var config = settings[Self.configKey] as? [String: Any] ?? [:]
            config[name] = object
            settings[Self.configKey] = config
        }
    }

    private func configObject(for name: String) throws -> [String: Any] {
        try configObject(for: name, in: readSettings())
    }

    private func configObject(for name: String, in settings: [String: Any]) throws -> [String: Any] {
        guard let config = settings[Self.configKey] else { return [:] }
        guard let config = config as? [String: Any] else { throw VozHomeError.malformedSettings(self.settings) }
        guard let object = config[name] else { return [:] }
        guard let object = object as? [String: Any] else { throw VozHomeError.malformedConfig(self.settings, name) }
        return object
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
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: self.settings, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.settings.path)
    }

    private func updateSettings(_ update: (inout [String: Any]) throws -> Void) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lock = root.appendingPathComponent(".settings.lock").path
        let descriptor = Darwin.open(lock, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { flock(descriptor, LOCK_UN) }
        guard fchmod(descriptor, 0o600) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var settings = try readSettings()
        try update(&settings)
        try writeSettings(settings)
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settings.path) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any] else {
            throw VozHomeError.malformedSettings(settings)
        }
        return object
    }
}
