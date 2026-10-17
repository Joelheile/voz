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
