import CoreGraphics
import Testing
@testable import Voz

private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1131)
private let tile = CGSize(width: 360, height: 64)

@MainActor
@Test func tileSitsCenteredBelowTheSettingsWindow() {
    let window = CGRect(x: 400, y: 300, width: 700, height: 600)
    #expect(PermissionTile.origin(for: tile, below: window, on: screen) == CGPoint(x: 570, y: 228))
}

@MainActor
@Test func tileMovesInsideTheWindowWhenThereIsNoRoomBelow() {
    let window = CGRect(x: 400, y: 20, width: 700, height: 600)
    #expect(PermissionTile.origin(for: tile, below: window, on: screen) == CGPoint(x: 570, y: 36))
}

@MainActor
@Test func tileStaysOnScreenNearTheEdge() {
    let window = CGRect(x: -200, y: 300, width: 300, height: 600)
    #expect(PermissionTile.origin(for: tile, below: window, on: screen).x == 8)
}
