import CoreGraphics
import Testing
@testable import VozCore

@Suite struct LevelBarsGeometryTests {
    private let range = LevelBarsGeometry.maxHeight - LevelBarsGeometry.minHeight

    @Test func silentBarsBreatheWithinASmallBand() {
        let ceiling = LevelBarsGeometry.minHeight + range * LevelBarsGeometry.breathingLevel
        var seen = Set<CGFloat>()
        for step in 0..<40 {
            for index in 0..<LevelBarsGeometry.barCount {
                let height = LevelBarsGeometry.height(level: 0, time: Double(step) * 0.05, index: index)
                #expect(height >= LevelBarsGeometry.minHeight)
                #expect(height <= ceiling + 0.0001)
                seen.insert(height)
            }
        }
        #expect(seen.count > 20)
    }

    @Test func loudSpeechReachesFarAboveBreathing() {
        let breathingCeiling = LevelBarsGeometry.minHeight + range * LevelBarsGeometry.breathingLevel
        var tallest: CGFloat = 0
        for step in 0..<40 {
            tallest = max(tallest, LevelBarsGeometry.height(level: 1, time: Double(step) * 0.05, index: 2))
        }
        #expect(tallest > breathingCeiling + 4)
        #expect(tallest <= LevelBarsGeometry.maxHeight + 0.0001)
    }

    @Test func heightsStayInsideBounds() {
        for levelStep in 0...10 {
            for timeStep in 0..<30 {
                for index in 0..<LevelBarsGeometry.barCount {
                    let height = LevelBarsGeometry.height(level: Float(levelStep) / 10, time: Double(timeStep) * 0.07, index: index)
                    #expect(height >= LevelBarsGeometry.minHeight)
                    #expect(height <= LevelBarsGeometry.maxHeight + 0.0001)
                }
            }
        }
    }

    @Test func centerBarIsTallerAndLayoutIsSymmetric() {
        let edge = LevelBarsGeometry.staticHeight(level: 0.8, index: 0)
        let center = LevelBarsGeometry.staticHeight(level: 0.8, index: 2)
        #expect(center > edge)
        #expect(edge == LevelBarsGeometry.staticHeight(level: 0.8, index: 4))
        #expect(LevelBarsGeometry.staticHeight(level: 1, index: 2) == LevelBarsGeometry.maxHeight)
    }

    @Test func quietSpeechIsLiftedAboveLinear() {
        let linear = LevelBarsGeometry.minHeight + range * 0.25
        #expect(LevelBarsGeometry.staticHeight(level: 0.25, index: 2) > linear + 1)
    }

    @Test func staticHeightIgnoresBreathingAndRespondsToLevel() {
        #expect(LevelBarsGeometry.staticHeight(level: 0, index: 2) == LevelBarsGeometry.minHeight)
        #expect(LevelBarsGeometry.staticHeight(level: 0.6, index: 2) > LevelBarsGeometry.staticHeight(level: 0.3, index: 2))
    }

    @Test func totalWidthCountsBarsAndGaps() {
        #expect(LevelBarsGeometry.totalWidth == 27)
    }
}
