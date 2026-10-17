import Foundation
import VozCore

let installedBun = ["BUN_PATH", "HOME"]
    .compactMap { ProcessInfo.processInfo.environment[$0] }
    .map { $0.hasSuffix("bun") ? URL(fileURLWithPath: $0) : URL(fileURLWithPath: $0).appendingPathComponent(".bun/bin/bun") }
    .first { FileManager.default.isExecutableFile(atPath: $0.path) }

let hostScript = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Extensions/host.ts")

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

func storedConfig(in home: VozHome) throws -> [String: [String: String]]? {
    let stored = try JSONSerialization.jsonObject(with: Data(contentsOf: home.settings)) as? [String: Any]
    return stored?["config"] as? [String: [String: String]]
}

final class RecordedActions: @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [HostAction] = []

    func append(_ action: HostAction) { lock.withLock { actions.append(action) } }
    var all: [HostAction] { lock.withLock { actions } }
}
