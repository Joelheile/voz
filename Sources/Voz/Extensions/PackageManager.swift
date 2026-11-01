import Foundation

enum PackagesError: Error, CustomStringConvertible {
    case alreadyInstalled(String)
    case notInstalled(String)
    case missing(URL)
    case notAFolder(URL)
    case failed(command: String, status: Int32, reason: String?)

    var description: String {
        switch self {
        case .alreadyInstalled(let path): "Already installed at \(path). Run voz update or voz remove first."
        case .notInstalled(let name): "No installed package matches \(name). Run voz list to see them."
        case .missing(let url): "No package at \(url.path)."
        case .notAFolder(let url): "\(url.path) is not a folder. Put the extension in a folder as index.ts, then run voz dev on the folder."
        case .failed(let command, let status, let reason?): "\(command) failed with status \(status): \(reason)"
        case .failed(let command, let status, nil): "\(command) failed with status \(status)."
        }
    }
}

/// Installs, updates and removes extension packages in `~/.voz`, for the terminal and the Extensions page
enum Packages {
    static let warning = "Packages run code on your Mac with your permissions and can read your transcripts. Review the source before you install."
    private static let home = VozHome()
    private static let git = "/usr/bin/git"

    static func install(_ raw: String) async throws -> PackageSource {
        let source = try PackageSource(parsing: raw, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let directory = source.directory(in: home)
        switch source {
        case .npm(_, let spec):
            let bun = try await BunRuntime.ensure()
            try preparePackagesManifest()
            try execute(bun.path, ["add", "--ignore-scripts", "--exact", spec], in: home.packages)
        case .git(_, _, let ref):
            guard !FileManager.default.fileExists(atPath: directory.path) else { throw PackagesError.alreadyInstalled(directory.path) }
            let bun = try await BunRuntime.ensure()
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("voz-clone-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            let branch = ref.map { ["--branch", $0] } ?? []
            try execute(git, ["clone", "--quiet", "--depth", "1"] + branch + [source.cloneURL!, staging.path])
            try installDependencies(in: staging, bun: bun)
            try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staging, to: directory)
        case .local(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { throw PackagesError.missing(url) }
        }
        let others = try installed().filter { $0.source.name != source.name }.map(\.raw)
        try home.setPackageSources(others + [source.description])
        notifyApp()
        return source
    }

    /// Returns the source it removed, as it was written in settings
    @discardableResult
    static func remove(_ target: String) async throws -> String {
        let packages = try installed()
        guard let match = packages.first(where: { $0.raw == target || $0.source.name == target }) else { throw PackagesError.notInstalled(target) }
        switch match.source {
        case .npm(let name, _):
            try execute(try await BunRuntime.ensure().path, ["remove", name], in: home.packages)
        case .git:
            try removeCheckout(match.source.directory(in: home))
        case .local:
            break
        }
        try home.setPackageSources(packages.filter { $0.raw != match.raw }.map(\.raw))
        notifyApp()
        return match.raw
    }

    /// Updates every package that isn't pinned to a version or ref, and returns how many
    static func updateAll() async throws -> Int {
        let packages = try installed().filter { !$0.source.isPinned }
        for package in packages { try await pull(package.source) }
        notifyApp()
        return packages.count
    }

    static func update(_ source: PackageSource) async throws {
        try await pull(source)
        notifyApp()
    }

    private static func pull(_ source: PackageSource) async throws {
        let bun = try await BunRuntime.ensure()
        switch source {
        case .npm(let name, _):
            try execute(bun.path, ["add", "--ignore-scripts", "--exact", "\(name)@latest"], in: home.packages)
        case .git:
            let directory = source.directory(in: home)
            try execute(git, ["-C", directory.path, "pull", "--ff-only"])
            try installDependencies(in: directory, bun: bun)
        case .local:
            break
        }
    }

    /// Loads a folder until `stop` returns, then unloads it, unless it was already installed
    static func develop(_ url: URL, while stop: () throws -> Void) throws {
        let source = PackageSource.local(url)
        let sources = try home.packageSources()
        let added = !sources.contains(source.description)
        if added { try home.setPackageSources(sources + [source.description]) }
        notifyApp()
        defer {
            if added { try? home.setPackageSources((try? home.packageSources())?.filter { $0 != source.description } ?? []) }
            notifyApp()
        }
        try stop()
    }

    private static func installed() throws -> [(raw: String, source: PackageSource)] {
        try home.packageSources().map { ($0, try PackageSource(parsing: $0, relativeTo: home.root)) }
    }

    private static func removeCheckout(_ directory: URL) throws {
        try FileManager.default.removeItem(at: directory)
        var parent = directory.deletingLastPathComponent()
        while parent.path.hasPrefix(home.packages.path + "/"), try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty {
            try FileManager.default.removeItem(at: parent)
            parent = parent.deletingLastPathComponent()
        }
    }

    private static func preparePackagesManifest() throws {
        let manifest = home.packages.appendingPathComponent("package.json")
        guard !FileManager.default.fileExists(atPath: manifest.path) else { return }
        try FileManager.default.createDirectory(at: home.packages, withIntermediateDirectories: true)
        try Data(#"{ "name": "voz-packages", "private": true }"#.utf8).write(to: manifest)
    }

    private static func installDependencies(in directory: URL, bun: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("package.json").path) else { return }
        try execute(bun.path, ["install", "--ignore-scripts", "--production"], in: directory)
    }

    private static func execute(_ executable: String, _ arguments: [String], in directory: URL? = nil) throws {
        let result = try BunRuntime.run(executable, arguments, in: directory)
        guard result.status == 0 else {
            let reason = result.errorOutput.split(whereSeparator: \.isNewline).last.map(String.init)
            throw PackagesError.failed(command: URL(fileURLWithPath: executable).lastPathComponent, status: result.status, reason: reason)
        }
    }

    private static func notifyApp() {
        DistributedNotificationCenter.default().postNotificationName(VozHome.changedNotification, object: nil, deliverImmediately: true)
    }
}

enum CommandLineToolError: Error, CustomStringConvertible {
    case occupied(String)
    case cancelled
    case failed(String)

    var description: String {
        switch self {
        case .occupied(let path): "\(path) already exists and is not a voz link. Remove it, then try again."
        case .cancelled: "Voz did not add the voz command."
        case .failed(let reason): "Could not add the voz command: \(reason)"
        }
    }
}

enum CommandLineTool {
    static let link = URL(fileURLWithPath: "/usr/local/bin/voz")

    static var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == executable
    }

    static func install() throws {
        let files = FileManager.default
        let existing = try? files.destinationOfSymbolicLink(atPath: link.path)
        guard existing != executable else { return }
        let replacesOldVoz = existing?.hasSuffix("voz.app/Contents/MacOS/voz") == true
        guard replacesOldVoz || (try? files.attributesOfItem(atPath: link.path)) == nil else { throw CommandLineToolError.occupied(link.path) }
        do {
            if replacesOldVoz { try files.removeItem(at: link) }
            try files.createSymbolicLink(atPath: link.path, withDestinationPath: executable)
        } catch {
            try installAsAdministrator()
        }
    }

    private static func installAsAdministrator() throws {
        var error: NSDictionary?
        NSAppleScript(source: administratorScript(linking: executable))?.executeAndReturnError(&error)
        guard let error else { return }
        let userCancelled = error[NSAppleScript.errorNumber] as? Int == -128
        if userCancelled { throw CommandLineToolError.cancelled }
        throw CommandLineToolError.failed(error[NSAppleScript.errorMessage] as? String ?? "\(error)")
    }

    static func administratorScript(linking executable: String) -> String {
        let command = "mkdir -p /usr/local/bin && ln -sf \(shellQuoted(executable)) \(link.path)"
        let quoted = "\"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return "do shell script \(quoted) with prompt \"Voz needs your password to add the voz command to Terminal.\" with administrator privileges"
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static var executable: String {
        Bundle.main.executableURL!.path
    }
}
