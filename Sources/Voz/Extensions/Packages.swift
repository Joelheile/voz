import Foundation

enum PackageSourceError: Error, Equatable, CustomStringConvertible {
    case unrecognized(String)

    var description: String {
        switch self {
        case .unrecognized(let raw): "Unrecognized package source \"\(raw)\". Use npm:<name>, git:<host>/<owner>/<repo>[@ref], an https URL, or a local path."
        }
    }
}

enum PackageSource: Equatable, Sendable, CustomStringConvertible {
    case npm(name: String, spec: String)
    case git(host: String, path: String, ref: String?)
    case local(URL)

    init(parsing raw: String, relativeTo base: URL) throws(PackageSourceError) {
        if raw.hasPrefix("npm:") {
            let spec = String(raw.dropFirst(4))
            let name = Self.npmName(spec)
            let version = spec.dropFirst(name.count + 1)
            guard Self.isNpmName(name), spec == name || Self.isSafeToken(version) else { throw .unrecognized(raw) }
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
            guard let source = try? PackageSource(parsing: "npm:\(raw)", relativeTo: base) else { throw .unrecognized(raw) }
            self = source
        }
    }

    var description: String {
        switch self {
        case .npm(_, let spec): "npm:\(spec)"
        case .git(let host, let path, let ref): "git:\(host)/\(path)" + (ref.map { "@\($0)" } ?? "")
        case .local(let url): url.path
        }
    }

    var name: String {
        switch self {
        case .npm(let name, _): name
        case .git(_, let path, _): String(path.split(separator: "/").last ?? "")
        case .local(let url): url.lastPathComponent
        }
    }

    var isPinned: Bool {
        switch self {
        case .npm(let name, let spec): spec != name
        case .git(_, _, let ref): ref != nil
        case .local: false
        }
    }

    var cloneURL: String? {
        guard case .git(let host, let path, _) = self else { return nil }
        return "https://\(host)/\(path)"
    }

    func directory(in home: VozHome) -> URL {
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
        guard parts.count == 2, isSafeToken(parts[0][...]), isSafePath(parts[1]), ref.map(isSafePath) != false else { throw .unrecognized(raw) }
        return .git(host: parts[0], path: parts[1], ref: ref)
    }

    private static func isNpmName(_ name: String) -> Bool {
        name.wholeMatch(of: /(@[a-z0-9~][a-z0-9._~-]*\/)?[a-z0-9~][a-z0-9._~-]*/) != nil
    }

    private static func isSafePath(_ path: String) -> Bool {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        return segments.allSatisfy { isSafeToken($0) && $0 != "." && $0 != ".." }
    }

    private static func isSafeToken(_ token: Substring) -> Bool {
        token.wholeMatch(of: /[A-Za-z0-9_.~^<>=*+][A-Za-z0-9_.~^<>=*+-]*/) != nil
    }
}

enum PackageOrder: String, CaseIterable, Sendable {
    case popular = "Popular"
    case recent = "Recent"
    case name = "A-Z"
}

struct PackageListing: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let summary: String?
    let version: String
    let publisher: String
    let monthlyDownloads: Int
    let published: Date?
    let page: URL?

    var id: String { name }

    static func decodeSearch(_ data: Data) throws -> [PackageListing] {
        try JSONDecoder().decode(SearchResult.self, from: data).objects
            .map(PackageListing.init)
            .ordered(by: .popular)
    }

    static func decodePackument(_ data: Data) throws -> PackageListing {
        try PackageListing(JSONDecoder().decode(Packument.self, from: data))
    }

    private init(_ packument: Packument) throws {
        guard let version = packument.distTags.latest else { throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "\(packument.name) has no latest version")) }
        name = packument.name
        summary = packument.description
        self.version = version
        publisher = packument.versions[version]?.npmUser?.name ?? "unknown"
        monthlyDownloads = 0
        published = packument.time[version].flatMap { try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0) }
        page = URL(string: "https://www.npmjs.com/package/\(packument.name)")
    }

    private init(_ object: SearchResult.Object) {
        name = object.package.name
        summary = object.package.description
        version = object.package.version
        publisher = object.package.publisher?.username ?? "unknown"
        monthlyDownloads = object.downloads?.monthly ?? 0
        published = object.package.date.flatMap { try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0) }
        page = object.package.links?.npm.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }
}

private struct Packument: Decodable {
    struct DistTags: Decodable { let latest: String? }
    struct Version: Decodable {
        struct User: Decodable { let name: String }
        let npmUser: User?
        enum CodingKeys: String, CodingKey { case npmUser = "_npmUser" }
    }

    let name: String
    let description: String?
    let distTags: DistTags
    let versions: [String: Version]
    let time: [String: String]

    enum CodingKeys: String, CodingKey { case name, description, distTags = "dist-tags", versions, time }
}

private struct SearchResult: Decodable {
    struct Object: Decodable {
        struct Package: Decodable {
            struct Publisher: Decodable { let username: String }
            struct Links: Decodable { let npm: String? }
            let name: String
            let description: String?
            let version: String
            let date: String?
            let publisher: Publisher?
            let links: Links?
        }

        struct Downloads: Decodable { let monthly: Int }
        let package: Package
        let downloads: Downloads?
    }

    let objects: [Object]
}

extension [PackageListing] {
    func ordered(by order: PackageOrder) -> [PackageListing] {
        switch order {
        case .popular: sorted { $0.monthlyDownloads > $1.monthlyDownloads }
        case .recent: sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        case .name: sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

enum ExtensionLink {
    static func packageName(in url: URL) -> String? {
        guard url.scheme == "voz", url.host() == "extensions" else { return nil }
        let name = String(url.path().dropFirst()).removingPercentEncoding ?? ""
        guard case .npm(let parsed, let spec)? = try? PackageSource(parsing: "npm:\(name)", relativeTo: URL(fileURLWithPath: "/")), parsed == spec else { return nil }
        return parsed
    }
}
