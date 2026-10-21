import CryptoKit
import Foundation

enum BunRuntimeError: Error, CustomStringConvertible {
    case checksumMismatch(String)
    case unzipFailed(Int32)
    case downloadFailed

    var description: String {
        switch self {
        case .downloadFailed: "Could not download Bun. Check your connection and try again."
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

    static func ensure(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let destination = try executable()
        if FileManager.default.isExecutableFile(atPath: destination.path) { return destination }
        Log.app.notice("Downloading Bun \(version)")
        let download: URL
        do {
            download = try await URLSession.shared.download(from: archive, delegate: DownloadProgress(report: progress)).0
        } catch let error as URLError {
            Log.app.error("Bun download failed: \(error.localizedDescription, privacy: .public)")
            throw BunRuntimeError.downloadFailed
        }
        let digest = SHA256.hash(data: try Data(contentsOf: download)).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw BunRuntimeError.checksumMismatch(digest) }
        let unpacked = FileManager.default.temporaryDirectory.appendingPathComponent("voz-bun-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: unpacked) }
        let status = try run("/usr/bin/ditto", ["-x", "-k", download.path, unpacked.path]).status
        guard status == 0 else { throw BunRuntimeError.unzipFailed(status) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: unpacked.appendingPathComponent("bun-darwin-aarch64/bun"), to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) throws -> (status: Int32, errorOutput: String) {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(["NO_COLOR": "1"]) { $1 }
        process.standardError = errors
        try process.run()
        var collected = Data()
        while case let chunk = errors.fileHandleForReading.availableData, !chunk.isEmpty {
            FileHandle.standardError.write(chunk)
            collected.append(chunk)
        }
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: collected, as: UTF8.self))
    }
}

private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
            report(progress.fractionCompleted)
        }
    }
}
