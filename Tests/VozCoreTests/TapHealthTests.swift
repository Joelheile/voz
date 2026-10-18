import Testing
@testable import VozCore

struct TapHealthTests {
    private func decide(trusted: Bool = true, hasTap: Bool = true, enabled: Bool = true, enableSucceeded: Bool = true) -> TapHealthAction {
        TapHealthAction.decide(accessibilityGranted: trusted, hasTap: hasTap, isEnabled: enabled, enableSucceeded: enableSucceeded)
    }

    @Test func healthyTapNeedsNothing() {
        #expect(decide() == .none)
    }

    @Test func revokedAccessibilityStopsTheTap() {
        #expect(decide(trusted: false) == .stop)
        #expect(decide(trusted: false, hasTap: false) == .none)
    }

    @Test func regrantedAccessibilityCreatesTheTap() {
        #expect(decide(hasTap: false) == .create)
    }

    @Test func disabledTapIsEnabledOrRecreated() {
        #expect(decide(enabled: false) == .enable)
        #expect(decide(enabled: false, enableSucceeded: false) == .recreate)
    }
}

struct TapHealthScheduleTests {
    @Test func missingTapIsRetriedQuickly() {
        #expect(TapHealthSchedule.interval(hasTap: false) < TapHealthSchedule.interval(hasTap: true))
        #expect(TapHealthSchedule.interval(hasTap: false) == 2)
    }

    @Test func healthyTapIsCheckedSeldom() {
        #expect(TapHealthSchedule.interval(hasTap: true) == 30)
    }
}
