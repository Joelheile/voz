import AppKit
import Testing
@testable import Voz

private let visible = NSRect(x: 0, y: 0, width: 1800, height: 1131)
private let anchor = NSRect(x: 1000, y: 1131, width: 32, height: 38)
private let small = CGSize(width: 416, height: 500)
private let tall = CGSize(width: 416, height: 760)

@MainActor
@Test func panelHangsBelowTheMenuBarIcon() throws {
    let frame = try #require(StatusItemController.panelFrame(size: small, anchor: anchor, current: nil, visible: visible))
    let taller = try #require(StatusItemController.panelFrame(size: tall, anchor: anchor, current: frame, visible: visible))
    #expect(taller.maxY == frame.maxY)
    #expect(taller.height == tall.height)
}

@MainActor
@Test func openPanelResizesFromItsTopWhenTheFullScreenMenuBarHides() throws {
    let open = try #require(StatusItemController.panelFrame(size: small, anchor: anchor, current: nil, visible: visible))
    let grown = try #require(StatusItemController.panelFrame(size: tall, anchor: nil, current: open, visible: visible))
    #expect(grown.maxY == open.maxY)
    #expect(grown.minX == open.minX)
    #expect(grown.height == tall.height)
    let shrunk = try #require(StatusItemController.panelFrame(size: small, anchor: nil, current: grown, visible: visible))
    #expect(shrunk == open)
}

@MainActor
@Test func closedPanelWaitsForTheMenuBarIcon() {
    #expect(StatusItemController.panelFrame(size: small, anchor: nil, current: nil, visible: visible) == nil)
}
