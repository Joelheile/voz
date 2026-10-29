import CoreGraphics
import Testing
@testable import Voz

@Test(arguments: [true, false])
func indicatorWindowLeavesRoomForThePreviewBelow(hasNotch: Bool) {
    let screen = ScreenMetrics(
        frame: CGRect(x: 1800, y: 200, width: 1800, height: 1169), safeAreaTop: hasNotch ? 38 : 0,
        leftAreaWidth: hasNotch ? 790 : nil, rightAreaWidth: hasNotch ? 790 : nil, visibleMaxY: 1345
    )
    let layout = IndicatorLayout.make(screen: screen)
    let frame = layout.windowFrame
    #expect(frame.midX == screen.frame.midX)
    #expect(frame.maxY == layout.panelFrame.maxY)
    #expect(frame.contains(layout.panelFrame))
    #expect(frame.width >= IndicatorLayout.previewWidth)
    #expect(frame.width >= layout.panelFrame.width + 2 * (IndicatorLayout.dropSwell + IndicatorLayout.dropShadowRoom))
    #expect(screen.frame.contains(frame))
}
