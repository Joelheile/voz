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

    @Test func newestSlotShowsTheLiveLevel() {
        let time = 100.7 * step
        #expect(LevelBarsGeometry.sampleTime(slot: LevelBarsGeometry.barCount, time: time) == time)
    }

    @Test func olderSlotsShowTheEndOfTheirTick() {
        let sample = LevelBarsGeometry.sampleTime(slot: LevelBarsGeometry.barCount - 1, time: 100.7 * step)
        #expect(abs(sample - 100 * step) < 1e-9)
    }

    @Test func barsKeepTheirSampleWhenTheRowSnapsBack() {
        for slot in 1...LevelBarsGeometry.barCount {
            let before = LevelBarsGeometry.sampleTime(slot: slot, time: 100.999999 * step)
            let after = LevelBarsGeometry.sampleTime(slot: slot - 1, time: 101 * step)
            #expect(abs(before - after) < 1e-6)
        }
    }

    @Test func heightSpansMinToMax() {
        #expect(LevelBarsGeometry.height(level: 0, taper: 1) == LevelBarsGeometry.minHeight)
        #expect(LevelBarsGeometry.height(level: 1, taper: 1) == LevelBarsGeometry.maxHeight)
        #expect(LevelBarsGeometry.height(level: 2, taper: 1) == LevelBarsGeometry.maxHeight)
    }

    @Test func barsShrinkToADotAtTheLeftEdge() {
        #expect(LevelBarsGeometry.height(level: 1, taper: 0) == LevelBarsGeometry.minHeight)
        #expect(LevelBarsGeometry.taper(slot: 0, time: 100 * step) == 0)
        #expect(LevelBarsGeometry.taper(slot: LevelBarsGeometry.barCount, time: 100 * step) == 1)
    }

    @Test func taperGrowsAsBarsMoveRight() {
        let tapers = (1...LevelBarsGeometry.barCount).map { LevelBarsGeometry.taper(slot: $0, time: 100.5 * step) }
        #expect(tapers == tapers.sorted())
        #expect(tapers.first! < tapers.last!)
    }
}
