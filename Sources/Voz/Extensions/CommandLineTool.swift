import Foundation

enum CommandLineToolError: Error, CustomStringConvertible {
    case occupied(String)
    case notWritable(String)

    var description: String {
        switch self {
        case .occupied(let path): "\(path) already exists and is not a voz link. Remove it, then try again."
        case .notWritable(let command): "Run this in Terminal: \(command)"
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
            throw CommandLineToolError.notWritable("sudo mkdir -p /usr/local/bin && sudo ln -sf \(shellQuoted(executable)) \(link.path)")
        }
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static var executable: String {
        Bundle.main.executableURL!.path
    }
}
