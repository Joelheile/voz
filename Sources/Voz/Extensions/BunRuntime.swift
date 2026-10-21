import CryptoKit
import Foundation

enum BunRuntimeError: Error, CustomStringConvertible {
    case checksumMismatch(String)
    case unzipFailed(Int32)

    var description: String {
        switch self {
        case .checksumMismatch(let actual): "Bun download checksum mismatch: got \(actual)"
        case .unzipFailed(let status): "Unzipping Bun failed with status \(status)"
        }
    }
}

enum BunRuntime {
    static let version = "1.4.3"
    private static let sha256 = "80afd4c069b46a6fa8f3ec520bebc750a7843e4a8d5b9583d29ad436c00a3403"
    private static let archive = URL(string: "https://github.com/oven-sh/bun/releases/download/bun-v\(version)/bun-darwin-aarch64.zip")!

    static func executable() throws -> URL {
        try AppStorage.directory().appendingPathComponent("bun/\(version)/bun")
    }

    static var isInstalled: Bool {
        (try? executable()).map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
    }

    static func ensure() async throws -> URL {
        let destination = try executable()
        if FileManager.default.isExecutableFile(atPath: destination.path) { return destination }
        Log.app.notice("Downloading Bun \(version)")
        let (download, _) = try await URLSession.shared.download(from: archive)
        let digest = SHA256.hash(data: try Data(contentsOf: download)).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw BunRuntimeError.checksumMismatch(digest) }
        let unpacked = FileManager.default.temporaryDirectory.appendingPathComponent("voz-bun-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: unpacked) }
        let status = try run("/usr/bin/ditto", ["-x", "-k", download.path, unpacked.path])
        guard status == 0 else { throw BunRuntimeError.unzipFailed(status) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: unpacked.appendingPathComponent("bun-darwin-aarch64/bun"), to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
