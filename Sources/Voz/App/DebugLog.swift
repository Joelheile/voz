import Foundation

/// One JSON line per dictation, transcribed file and extension message, kept on this Mac for debugging.
struct DebugLog: Sendable {
    static let shared = DebugLog(file: URL.homeDirectory.appending(path: "Library/Logs/Voz/voz-logs.jsonl"))
    static let maxBytes = 5_000_000
    private static let queue = DispatchQueue(label: "com.joelheile.voz.debug-log")

    let file: URL

    var previousFile: URL {
        file.deletingLastPathComponent().appending(path: file.deletingPathExtension().lastPathComponent + ".1.jsonl")
    }

    func write(_ step: String, _ fields: [String: Any]) {
        var entry = fields
        entry["step"] = step
        entry["time"] = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(.now)
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        line.append(0x0A)
        let file = file, previousFile = previousFile
        Self.queue.async { Self.append(line, to: file, rotatingTo: previousFile) }
    }

    func lastLines(_ count: Int) -> String {
        Self.queue.sync {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "" }
            return text.split(separator: "\n").suffix(count).joined(separator: "\n")
        }
    }

    private static func append(_ line: Data, to file: URL, rotatingTo previousFile: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int, size + line.count > maxBytes {
            try? manager.removeItem(at: previousFile)
            try? manager.moveItem(at: file, to: previousFile)
        }
        guard let handle = try? FileHandle(forWritingTo: file) else {
            manager.createFile(atPath: file.path, contents: line, attributes: [.posixPermissions: 0o600])
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
