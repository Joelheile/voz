import CoreGraphics
import Testing
@testable import Voz

private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)

@Test func menuBarIconUnderTheNotchIsHidden() {
    #expect(MenuBarNotch.hides(CGRect(x: 880, y: 1131, width: 36, height: 38), screen: screen, leftWidth: 790, rightWidth: 790))
}

@Test func menuBarIconBesideTheNotchIsVisible() {
    #expect(!MenuBarNotch.hides(CGRect(x: 1153, y: 1131, width: 32, height: 38), screen: screen, leftWidth: 790, rightWidth: 790))
    #expect(!MenuBarNotch.hides(CGRect(x: 740, y: 1131, width: 36, height: 38), screen: screen, leftWidth: 790, rightWidth: 790))
}

@Test func notchOnASecondScreenUsesThatScreensPosition() {
    let right = CGRect(x: 1800, y: 0, width: 1800, height: 1169)
    #expect(MenuBarNotch.hides(CGRect(x: 2680, y: 1131, width: 36, height: 38), screen: right, leftWidth: 790, rightWidth: 790))
    #expect(!MenuBarNotch.hides(CGRect(x: 880, y: 1131, width: 36, height: 38), screen: right, leftWidth: 790, rightWidth: 790))
}
