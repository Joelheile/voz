public enum AnalyticsValue: Equatable, Sendable {
    case integer(Int)
    case number(Double)
    case flag(Bool)
    case text(String)
}
