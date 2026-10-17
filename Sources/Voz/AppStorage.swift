import Foundation

enum AppStorage {
    static let directoryPermissions = 0o700
    static let filePermissions = 0o600

    static func directory() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("voz", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        try FileManager.default.setAttributes([.posixPermissions: directoryPermissions], ofItemAtPath: directory.path)
        return directory
    }

    static func restrict(fileAt path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: filePermissions], ofItemAtPath: path)
    }
}
