import Testing
@testable import VozCore

struct LevelBarsGeometryTests {
    private let step = LevelBarsGeometry.secondsPerBar

    @Test func scrollStartsAtZeroOnEachBar() {
        #expect(LevelBarsGeometry.scrollOffset(time: 100 * step) == 0)
    }

    @Test func scrollMovesLeftWithinABar() {
        let offset = LevelBarsGeometry.scrollOffset(time: 100.5 * step)
        #expect(abs(offset + LevelBarsGeometry.pitch / 2) < 0.001)
    }

    @Test func newestSlotShowsTheCurrentTick() {
        let sample = LevelBarsGeometry.sampleTime(slot: LevelBarsGeometry.barCount, time: 100.7 * step)
        #expect(abs(sample - (100 * step - LevelBarsGeometry.latency)) < 1e-9)
    }

    @Test func barsKeepTheirSampleWhenTheRowSnapsBack() {
        for slot in 1...LevelBarsGeometry.barCount {
            let before = LevelBarsGeometry.sampleTime(slot: slot, time: 100.999 * step)
            let after = LevelBarsGeometry.sampleTime(slot: slot - 1, time: 101 * step)
            #expect(abs(before - after) < 1e-9)
        }
    }

    @Test func heightSpansMinToMax() {
        #expect(LevelBarsGeometry.height(level: 0) == LevelBarsGeometry.minHeight)
        #expect(LevelBarsGeometry.height(level: 1) == LevelBarsGeometry.maxHeight)
        #expect(LevelBarsGeometry.height(level: 2) == LevelBarsGeometry.maxHeight)
    }
}
