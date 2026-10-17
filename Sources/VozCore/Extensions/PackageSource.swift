import Foundation

public enum PackageSourceError: Error, Equatable, CustomStringConvertible {
    case unrecognized(String)

    public var description: String {
        switch self {
        case .unrecognized(let raw): "Unrecognized package source \"\(raw)\". Use npm:<name>, git:<host>/<owner>/<repo>[@ref], an https URL, or a local path."
        }
    }
}

public enum PackageSource: Equatable, Sendable, CustomStringConvertible {
    case npm(name: String, spec: String)
    case git(host: String, path: String, ref: String?)
    case local(URL)

    public init(parsing raw: String, relativeTo base: URL) throws(PackageSourceError) {
        if raw.hasPrefix("npm:") {
            let spec = String(raw.dropFirst(4))
            let name = Self.npmName(spec)
            guard !name.isEmpty else { throw .unrecognized(raw) }
            self = .npm(name: name, spec: spec)
        } else if raw.hasPrefix("git:") {
            self = try Self.git(String(raw.dropFirst(4)), raw: raw)
        } else if raw.hasPrefix("https://") || raw.hasPrefix("http://") {
            self = try Self.git(String(raw.drop(while: { $0 != "/" }).dropFirst(2)), raw: raw)
        } else if raw.hasPrefix("/") || raw.hasPrefix(".") || raw.hasPrefix("~") {
            let expanded = NSString(string: raw).expandingTildeInPath
            let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded)
            self = .local(url.standardizedFileURL)
        } else {
            throw .unrecognized(raw)
        }
    }

    public var description: String {
        switch self {
        case .npm(_, let spec): "npm:\(spec)"
        case .git(let host, let path, let ref): "git:\(host)/\(path)" + (ref.map { "@\($0)" } ?? "")
        case .local(let url): url.path
        }
    }

    public var name: String {
        switch self {
        case .npm(let name, _): name
        case .git(_, let path, _): String(path.split(separator: "/").last ?? "")
        case .local(let url): url.lastPathComponent
        }
    }

    public var isPinned: Bool {
        switch self {
        case .npm(let name, let spec): spec != name
        case .git(_, _, let ref): ref != nil
        case .local: false
        }
    }

    public var cloneURL: String? {
        guard case .git(let host, let path, _) = self else { return nil }
        return "https://\(host)/\(path)"
    }

    public func directory(in home: VozHome) -> URL {
        switch self {
        case .npm(let name, _): home.packages.appendingPathComponent("node_modules/\(name)", isDirectory: true)
        case .git(let host, let path, _): home.packages.appendingPathComponent("git/\(host)/\(path)", isDirectory: true)
        case .local(let url): url
        }
    }

    private static func npmName(_ spec: String) -> String {
        let searchStart = spec.hasPrefix("@") ? spec.index(after: spec.startIndex) : spec.startIndex
        guard let at = spec[searchStart...].firstIndex(of: "@") else { return spec }
        return String(spec[..<at])
    }

    private static func git(_ location: String, raw: String) throws(PackageSourceError) -> PackageSource {
        var location = location
        var ref: String?
        if let at = location.lastIndex(of: "@"), location[..<at].contains("/") {
            ref = String(location[location.index(after: at)...])
            location = String(location[..<at])
        }
        if location.hasSuffix(".git") { location = String(location.dropLast(4)) }
        let parts = location.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty, ref?.isEmpty != true else { throw .unrecognized(raw) }
        return .git(host: parts[0], path: parts[1], ref: ref)
    }
}
