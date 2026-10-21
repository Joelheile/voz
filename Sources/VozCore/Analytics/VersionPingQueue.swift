import Foundation

public final class VersionPingQueue {
    private static let key = "pendingVersionPings"
    private let defaults: UserDefaults
    public private(set) var pending: [Data]

    public init(defaults: UserDefaults = .standard) throws {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            pending = try JSONDecoder().decode([Data].self, from: data)
        } else {
            pending = []
        }
    }

    public func enqueue(_ ping: VersionPing, version: String, projectToken: String) throws {
        pending.append(try ping.body(version: version, projectToken: projectToken))
        try save()
    }

    public func acknowledge(_ body: Data) throws {
        pending.removeAll { $0 == body }
        try save()
    }

    public func clear() throws {
        pending.removeAll()
        try save()
    }

    private func save() throws {
        defaults.set(try JSONEncoder().encode(pending), forKey: Self.key)
    }
}
