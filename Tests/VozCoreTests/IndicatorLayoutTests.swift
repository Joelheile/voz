import CoreGraphics
import Testing
@testable import VozCore

struct IndicatorLayoutTests {
    private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func notchedScreenWrapsTheNotch() {
        let screen = ScreenMetrics(frame: frame, safeAreaTop: 32, leftAreaWidth: 662, rightAreaWidth: 662, visibleMaxY: 950)
        let layout = IndicatorLayout.make(screen: screen)
        #expect(layout.style == .notch)
        #expect(layout.panelFrame.maxY == frame.maxY)
        #expect(layout.panelFrame.height == 32)
        #expect(layout.panelFrame.width == 188 + 2 * IndicatorLayout.sideWidth)
    }

    @Test func screenWithoutNotchFloatsAPillBelowTheMenuBar() {
        let screen = ScreenMetrics(frame: frame, safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil, visibleMaxY: 958)
        let layout = IndicatorLayout.make(screen: screen)
        let pill = layout.panelFrame.insetBy(dx: IndicatorLayout.shadowMargin, dy: IndicatorLayout.shadowMargin)
        #expect(layout.style == .floating)
        #expect(pill.size == IndicatorLayout.pillSize)
        #expect(pill.midX == frame.midX)
        #expect(pill.maxY == 958 - IndicatorLayout.pillGap)
    }
}
