import Testing
import VozCore

@Suite struct CleanupGuardTests {
    @Test func rejectsDroppedNegationsAndChangedTimes() {
        #expect(CleanupGuard.rejection(raw: "I think we should not ship until both are done", cleaned: "I think we should wait until both are done.") == .changedMeaning)
        #expect(CleanupGuard.rejection(raw: "we don't need the report", cleaned: "We need the report.") == .changedMeaning)
        #expect(CleanupGuard.rejection(raw: "der Termin ist am 15. Mai um halb drei", cleaned: "Der Termin ist am 15. Mai um 15:30 Uhr.") == .changedMeaning)
    }
}
