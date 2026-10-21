import Foundation

public enum ExtensionTemplateError: Error, Equatable, CustomStringConvertible {
    case invalidName(String)
    case exists(String)

    public var description: String {
        switch self {
        case .invalidName(let name): "\(name) is not a valid npm package name. Use lowercase letters, digits and dashes, such as voz-jira."
        case .exists(let path): "\(path) already exists."
        }
    }
}

public enum ExtensionTemplate {
    private static let placeholder = "{{name}}"
    private static var validName: Regex<(Substring, Substring?)> { /^(@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/ }

    public static func create(named name: String, in parent: URL, from resources: URL) throws -> URL {
        guard name.wholeMatch(of: validName) != nil else { throw ExtensionTemplateError.invalidName(name) }
        let folder = parent.appendingPathComponent(String(name.split(separator: "/").last!), isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw ExtensionTemplateError.exists(folder.path) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: resources.appendingPathComponent("template", isDirectory: true), to: folder)
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let text = try String(contentsOf: file, encoding: .utf8)
            try text.replacingOccurrences(of: placeholder, with: name).write(to: file, atomically: true, encoding: .utf8)
        }
        try VozHome.writeTypes(into: folder, from: resources)
        return folder
    }

    public static func mapsTypes(in folder: URL) -> Bool {
        let config = try? String(contentsOf: folder.appendingPathComponent("tsconfig.json"), encoding: .utf8)
        return config?.contains("./voz.d.ts") == true
    }
}
