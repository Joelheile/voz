public enum AnalyticsValue: Equatable, Sendable {
    case integer(Int)
    case number(Double)
    case flag(Bool)
    case label(String)
    case version(String)
}
