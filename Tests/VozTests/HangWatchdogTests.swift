import Synchronization
import Testing
@testable import Voz

@MainActor @Suite(.serialized)
struct HangWatchdogTests {
    @Test func reportsABlockedMainThreadOnce() async throws {
        let hangs = Atomic<Int>(0)
        let watchdog = HangWatchdog(seconds: 0.2) { hangs.add(1, ordering: .relaxed) }
        watchdog.start()
        blockCurrentThread(seconds: 1)
        try await Task.sleep(for: .milliseconds(500))
        watchdog.stop()
        #expect(hangs.load(ordering: .relaxed) == 1)
    }

    @Test func staysQuietWhileTheMainThreadResponds() async throws {
        let hangs = Atomic<Int>(0)
        let watchdog = HangWatchdog(seconds: 0.2) { hangs.add(1, ordering: .relaxed) }
        watchdog.start()
        try await Task.sleep(for: .seconds(1))
        watchdog.stop()
        #expect(hangs.load(ordering: .relaxed) == 0)
    }
}
