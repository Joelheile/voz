import Foundation

public struct PackageListing: Equatable, Identifiable, Sendable {
    public let name: String
    public let summary: String?
    public let version: String
    public let publisher: String
    public let weeklyDownloads: Int
    public let page: URL?

    public var id: String { name }

    public static func decodeSearch(_ data: Data) throws -> [PackageListing] {
        try JSONDecoder().decode(SearchResult.self, from: data).objects
            .map(PackageListing.init)
            .sorted { $0.weeklyDownloads > $1.weeklyDownloads }
    }

    private init(_ object: SearchResult.Object) {
        name = object.package.name
        summary = object.package.description
        version = object.package.version
        publisher = object.package.publisher?.username ?? "unknown"
        weeklyDownloads = object.downloads?.weekly ?? 0
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
            let publisher: Publisher?
            let links: Links?
        }

        struct Downloads: Decodable { let weekly: Int }
        let package: Package
        let downloads: Downloads?
    }

    let objects: [Object]
}
