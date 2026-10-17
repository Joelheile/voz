import Foundation
import VozCore

enum PackageCLIError: Error, CustomStringConvertible {
    case usage
    case alreadyInstalled(String)
    case notInstalled(String)
    case missing(URL)
    case failed(String, Int32)

    var description: String {
        switch self {
        case .usage: "usage: voz install <npm:name | git:host/owner/repo[@ref] | https URL | path>\n       voz remove <source or name>\n       voz list\n       voz update"
        case .alreadyInstalled(let path): "Already installed at \(path). Run voz update or voz remove first."
        case .notInstalled(let name): "No installed package matches \(name)."
        case .missing(let url): "No package at \(url.path)."
        case .failed(let command, let status): "\(command) failed with status \(status)."
        }
    }
}

enum PackageCLI {
    private static let home = VozHome()
    private static let git = "/usr/bin/git"

    static func run(_ arguments: [String]) async -> Int32? {
        guard arguments.count > 1, ["install", "remove", "list", "update"].contains(arguments[1]) else { return nil }
        do {
            switch (arguments[1], arguments.dropFirst(2).first) {
            case ("install", let source?): try await install(source)
            case ("remove", let target?): try remove(target)
            case ("list", nil): try list()
            case ("update", nil): try await update()
            default: throw PackageCLIError.usage
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            return 1
        }
    }

    private static func install(_ raw: String) async throws {
        let source = try PackageSource(parsing: raw, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let directory = source.directory(in: home)
        print("Packages run code on your Mac with your permissions and can read your transcripts. Review the source before you install.")
        switch source {
        case .npm(_, let spec):
            let bun = try await BunRuntime.ensure()
            try preparePackagesManifest()
            try execute(bun.path, ["add", "--ignore-scripts", "--exact", spec], in: home.packages)
        case .git(_, _, let ref):
            guard !FileManager.default.fileExists(atPath: directory.path) else { throw PackageCLIError.alreadyInstalled(directory.path) }
            let bun = try await BunRuntime.ensure()
            try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            let branch = ref.map { ["--branch", $0] } ?? []
            try execute(git, ["clone", "--depth", "1"] + branch + [source.cloneURL!, directory.path])
            try installDependencies(in: directory, bun: bun)
        case .local(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { throw PackageCLIError.missing(url) }
        }
        let others = try installed().filter { $0.source.name != source.name }.map(\.raw)
        try home.setPackageSources(others + [source.description])
        notifyApp()
        print("Installed \(source.description)")
    }

    private static func remove(_ target: String) throws {
        let packages = try installed()
        guard let match = packages.first(where: { $0.raw == target || $0.source.name == target }) else { throw PackageCLIError.notInstalled(target) }
        switch match.source {
        case .npm(let name, _):
            try execute(try BunRuntime.executable().path, ["remove", name], in: home.packages)
        case .git:
            try FileManager.default.removeItem(at: match.source.directory(in: home))
        case .local:
            break
        }
        try home.setPackageSources(packages.filter { $0.raw != match.raw }.map(\.raw))
        notifyApp()
        print("Removed \(match.raw)")
    }

    private static func list() throws {
        let packages = try home.packageSources()
        if packages.isEmpty { print("No packages installed.") }
        for package in packages { print(package) }
        let loose = (try? FileManager.default.contentsOfDirectory(atPath: home.extensions.path))?.filter { !$0.hasPrefix(".") }.sorted() ?? []
        for file in loose { print("\(home.extensions.path)/\(file)") }
    }

    private static func update() async throws {
        let packages = try installed()
        let bun = try await BunRuntime.ensure()
        for package in packages where !package.source.isPinned {
            switch package.source {
            case .npm(let name, _):
                try execute(bun.path, ["add", "--ignore-scripts", "--exact", "\(name)@latest"], in: home.packages)
            case .git:
                let directory = package.source.directory(in: home)
                try execute(git, ["-C", directory.path, "pull", "--ff-only"])
                try installDependencies(in: directory, bun: bun)
            case .local:
                break
            }
        }
        notifyApp()
        print("Updated \(packages.count) package\(packages.count == 1 ? "" : "s")")
    }

    private static func installed() throws -> [(raw: String, source: PackageSource)] {
        try home.packageSources().map { ($0, try PackageSource(parsing: $0, relativeTo: home.root)) }
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
        let status = try BunRuntime.run(executable, arguments, in: directory)
        guard status == 0 else { throw PackageCLIError.failed(([executable] + arguments).joined(separator: " "), status) }
    }

    private static func notifyApp() {
        DistributedNotificationCenter.default().postNotificationName(VozHome.changedNotification, object: nil, deliverImmediately: true)
    }
}
