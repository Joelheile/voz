public struct UsageSession {
    private var lastCheckpoint: Int

    public init(startedAt: Int) {
        lastCheckpoint = startedAt
    }

    public mutating func checkpoint(at seconds: Int) -> Int {
        let elapsed = max(0, seconds - lastCheckpoint)
        lastCheckpoint = seconds
        return elapsed
    }
}

public enum SessionState: String, Sendable {
    case started
    case heartbeat
    case ended
}
