import CoreGraphics
import Testing
@testable import VozCore

@Suite struct IndicatorLayoutTests {
    private let notchScreen = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        safeAreaTop: 38,
        leftAreaWidth: 790,
        rightAreaWidth: 790,
        visibleMaxY: 1130
    )
    private let plainScreen = ScreenMetrics(
        frame: CGRect(x: 1800, y: 100, width: 2560, height: 1440),
        safeAreaTop: 0,
        leftAreaWidth: nil,
        rightAreaWidth: nil,
        visibleMaxY: 1516
    )

    @Test func notchSizeComesFromAuxiliaryAreas() {
        #expect(notchScreen.notchSize == CGSize(width: 220, height: 38))
        #expect(notchScreen.menuBarHeight == 38)
    }

    @Test func screenWithoutAuxiliaryAreasHasNoNotch() {
        #expect(plainScreen.notchSize == nil)
        #expect(plainScreen.menuBarHeight == 24)
    }

    @Test func notchPanelIsFlushWithTopAndCenteredOnNotch() {
        let layout = IndicatorLayout.make(style: .notch, screen: notchScreen)
        #expect(layout.style == .notch)
        #expect(layout.panelFrame == CGRect(x: 734, y: 1131, width: 332, height: 38))
        #expect(layout.panelFrame.midX == 900)
        #expect(layout.panelFrame.maxY == 1169)
        #expect(layout.collapsedWidth == 222)
    }

    @Test func notchStyleFallsBackToPillWithoutNotch() {
        let layout = IndicatorLayout.make(style: .notch, screen: plainScreen)
        #expect(layout.style == .pill)
    }

    @Test func pillSitsBelowMenuBarOnSecondScreen() {
        let layout = IndicatorLayout.make(style: .pill, screen: plainScreen)
        #expect(abs(layout.panelFrame.midX - 3080) < 0.001)
        #expect(layout.panelFrame.maxY == 1540 - 24 - IndicatorLayout.pillGap)
        #expect(layout.panelFrame.size == IndicatorLayout.pillSize)
    }

    @Test func pillStyleStaysPillOnNotchScreen() {
        let layout = IndicatorLayout.make(style: .pill, screen: notchScreen)
        #expect(layout.panelFrame.maxY == 1169 - 38 - IndicatorLayout.pillGap)
    }

    @Test func screenChoicePicksLargestOverlap() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)]
        #expect(ScreenChoice.index(containing: CGRect(x: 60, y: 10, width: 100, height: 50), in: frames) == 1)
        #expect(ScreenChoice.index(containing: CGRect(x: 10, y: 10, width: 60, height: 50), in: frames) == 0)
        #expect(ScreenChoice.index(containing: CGRect(x: 500, y: 500, width: 10, height: 10), in: frames) == nil)
    }
}
