import Foundation
import VozCore

let installedBun = ["BUN_PATH", "HOME"]
    .compactMap { ProcessInfo.processInfo.environment[$0] }
    .map { $0.hasSuffix("bun") ? URL(fileURLWithPath: $0) : URL(fileURLWithPath: $0).appendingPathComponent(".bun/bin/bun") }
    .first { FileManager.default.isExecutableFile(atPath: $0.path) }

let hostScript = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Extensions/host.ts")

let extensionResources = hostScript.deletingLastPathComponent()

func temporaryHome() -> VozHome {
    VozHome(root: FileManager.default.temporaryDirectory.appendingPathComponent("voz-home-\(UUID().uuidString)"))
}

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: path)
}

func writeFile(_ contents: String, named name: String, in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
}

func fileContents(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

func posixPermissions(_ url: URL) -> Int? {
    try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
}

final class RecordedActions: @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [HostAction] = []

    func append(_ action: HostAction) { lock.withLock { actions.append(action) } }
    var all: [HostAction] { lock.withLock { actions } }
}

private struct HostLaunch: Encodable {
    let home: String
    let settings: String
    let extensionsDirectory: String
    let packages: [String] = []
}

func hostOutlivesClosedInput(home: VozHome) async throws -> Bool {
    let arguments = HostLaunch(home: home.root.path, settings: home.settings.path, extensionsDirectory: home.extensions.path)
    let process = Process()
    process.executableURL = installedBun
    process.arguments = ["--no-install", hostScript.path, String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)]
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    defer { if process.isRunning { process.terminate() } }
    try input.fileHandleForWriting.close()
    for _ in 0..<30 where process.isRunning { try await Task.sleep(for: .milliseconds(100)) }
    return process.isRunning
}

func processIsGone(_ pid: Int32) async throws -> Bool {
    for _ in 0..<30 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(100)) }
    return kill(pid, 0) != 0
}

func localSource(_ path: String) -> PackageSource {
    .local(URL(fileURLWithPath: path))
}
