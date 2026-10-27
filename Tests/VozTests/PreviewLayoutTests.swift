import CoreGraphics
import Testing
@testable import Voz

@Test(arguments: [true, false])
func previewSitsBelowIndicatorOnTheSameScreen(hasNotch: Bool) {
    let screen = ScreenMetrics(
        frame: CGRect(x: 1800, y: 200, width: 1800, height: 1169), safeAreaTop: hasNotch ? 38 : 0,
        leftAreaWidth: hasNotch ? 790 : nil, rightAreaWidth: hasNotch ? 790 : nil, visibleMaxY: 1345
    )
    let layout = IndicatorLayout.make(screen: screen)
    let frame = layout.previewFrame(size: CGSize(width: 360, height: 100))
    #expect(frame.midX == screen.frame.midX)
    let bottom = layout.panelFrame.minY + (hasNotch ? 0 : IndicatorLayout.shadowMargin)
    #expect(frame.maxY == bottom - IndicatorLayout.pillGap)
    #expect(screen.frame.contains(frame))
}
