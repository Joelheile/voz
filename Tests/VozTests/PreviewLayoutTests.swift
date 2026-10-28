import CoreGraphics
import Testing
@testable import Voz

@Test(arguments: [
    CGRect(x: 1800, y: 270, width: 1800, height: 1075),
    CGRect(x: 0, y: 0, width: 1512, height: 958),
])
func indicatorSitsAboveTheDockWithRoomForThePreviewAbove(visibleFrame: CGRect) {
    let layout = IndicatorLayout.make(visibleFrame: visibleFrame)
    let frame = layout.windowFrame
    #expect(frame.midX == visibleFrame.midX)
    #expect(frame.minY == layout.panelFrame.minY)
    #expect(frame.minY >= visibleFrame.minY)
    #expect(frame.contains(layout.panelFrame))
    #expect(frame.width >= IndicatorLayout.previewWidth)
    #expect(visibleFrame.contains(frame))
}
