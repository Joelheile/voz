public enum TapHealthAction: Equatable, Sendable {
    case none
    case stop
    case create
    case enable
    case recreate

    public static func decide(accessibilityGranted: Bool, hasTap: Bool, isEnabled: Bool, enableSucceeded: Bool) -> TapHealthAction {
        guard accessibilityGranted else { return hasTap ? .stop : .none }
        guard hasTap else { return .create }
        guard !isEnabled else { return .none }
        return enableSucceeded ? .enable : .recreate
    }
}

public enum TapHealthSchedule {
    public static let healthyInterval = 30.0
    public static let missingInterval = 2.0

    public static func interval(hasTap: Bool) -> Double {
        hasTap ? healthyInterval : missingInterval
    }
}
