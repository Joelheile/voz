import Foundation

public enum PackageOrder: String, CaseIterable, Sendable {
    case popular = "Popular"
    case recent = "Recent"
    case name = "A-Z"
}

public struct PackageListing: Equatable, Identifiable, Sendable {
    public let name: String
    public let summary: String?
    public let version: String
    public let publisher: String
    public let monthlyDownloads: Int
    public let published: Date?
    public let page: URL?

    public var id: String { name }

    public static func decodeSearch(_ data: Data) throws -> [PackageListing] {
        try JSONDecoder().decode(SearchResult.self, from: data).objects
            .map(PackageListing.init)
            .ordered(by: .popular)
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
    public func ordered(by order: PackageOrder) -> [PackageListing] {
        switch order {
        case .popular: sorted { $0.monthlyDownloads > $1.monthlyDownloads }
        case .recent: sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        case .name: sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
