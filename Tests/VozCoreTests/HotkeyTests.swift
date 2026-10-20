import CoreGraphics
import Testing
@testable import VozCore

private final class Driver {
    var machine: HotkeyStateMachine
    var isRecording = false

    init(hotkey: Hotkey = .rightCommand, holdToTalk: Bool = false) {
        machine = HotkeyStateMachine(hotkey: hotkey, holdToTalk: holdToTalk)
    }

    @discardableResult
    func press(at time: Double, keyCode: UInt16 = 54, flags: CGEventFlags = .maskCommand) -> HotkeyAction {
        machine.handle(.flagsChanged(keyCode: keyCode, flags: flags, time: time), isRecording: isRecording)
    }

    @discardableResult
    func release(at time: Double, keyCode: UInt16 = 54) -> HotkeyAction {
        machine.handle(.flagsChanged(keyCode: keyCode, flags: [], time: time), isRecording: isRecording)
    }

    @discardableResult
    func keyDown(_ keyCode: UInt16, flags: CGEventFlags, at time: Double = 0, isRepeat: Bool = false) -> HotkeyAction {
        machine.handle(.keyDown(keyCode: keyCode, flags: flags, time: time, isRepeat: isRepeat), isRecording: isRecording)
    }

    @discardableResult
    func keyUp(_ keyCode: UInt16, at time: Double) -> HotkeyAction {
        machine.handle(.keyUp(keyCode: keyCode, time: time), isRecording: isRecording)
    }
}

private let controlOptionSpace = Hotkey(keyCode: 49, modifiers: [.maskControl, .maskAlternate])
private let controlOptionFlags: CGEventFlags = [.maskControl, .maskAlternate]

@Suite struct HotkeyTests {
    @Test func modifierTapTogglesOnlyOnQuickReleaseOfTheRightKey() {
        let driver = Driver()
        #expect(driver.press(at: 0) == .none)
        #expect(driver.release(at: 0.1) == .toggle)
        driver.press(at: 1)
        #expect(driver.release(at: 3) == .none)
        driver.press(at: 4, keyCode: 55)
        #expect(driver.release(at: 4.1, keyCode: 55) == .none)
        #expect(driver.press(at: 5, flags: [.maskCommand, .maskShift]) == .none)
        #expect(driver.release(at: 5.1) == .none)

        let fn = Driver(hotkey: Hotkey(keyCode: 63, modifiers: []))
        fn.press(at: 0, keyCode: 63, flags: .maskSecondaryFn)
        #expect(fn.release(at: 0.1, keyCode: 63) == .toggle)
    }

    @Test(arguments: ["key", "pointer", "modifier"])
    func interruptionWhileHeldCancelsTheTapButNotTheNextOne(interruption: String) {
        let driver = Driver()
        driver.press(at: 0)
        switch interruption {
        case "key": driver.keyDown(8, flags: .maskCommand)
        case "pointer": _ = driver.machine.handle(.pointerDown)
        default: driver.press(at: 0.05, keyCode: 56, flags: [.maskCommand, .maskShift])
        }
        #expect(driver.release(at: 0.2) == .none)
        driver.press(at: 1)
        #expect(driver.release(at: 1.1) == .toggle)
    }

    @Test func comboTogglesOnExactKeyDownAndIgnoresRepeatsAndKeyUp() {
        let driver = Driver(hotkey: controlOptionSpace)
        #expect(driver.keyDown(49, flags: .maskControl) == .none)
        #expect(driver.keyDown(8, flags: controlOptionFlags) == .none)
        #expect(driver.keyDown(49, flags: controlOptionFlags) == .toggle)
        #expect(driver.keyDown(49, flags: controlOptionFlags, isRepeat: true) == .none)
        #expect(driver.keyUp(49, at: 0.1) == .none)
        #expect(driver.press(at: 0.2, keyCode: 59, flags: .maskControl) == .none)
    }

    @Test func holdModeStartsOnPressAndStopsOnlyAfterALongHold() {
        let driver = Driver(holdToTalk: true)
        #expect(driver.press(at: 0) == .start)
        driver.isRecording = true
        #expect(driver.release(at: 0.2) == .none)
        #expect(driver.press(at: 5) == .stop)
        #expect(driver.release(at: 8) == .none)

        let chord = Driver(holdToTalk: true)
        chord.press(at: 0)
        chord.isRecording = true
        chord.keyDown(8, flags: .maskCommand)
        #expect(chord.release(at: 0.2) == .stop)
    }

    @Test func holdModeComboStartsOnKeyDownAndStopsOnKeyUp() {
        let driver = Driver(hotkey: controlOptionSpace, holdToTalk: true)
        #expect(driver.keyDown(49, flags: controlOptionFlags, at: 0) == .start)
        driver.isRecording = true
        _ = driver.machine.handle(.pointerDown)
        #expect(driver.keyDown(49, flags: controlOptionFlags, at: 0.5, isRepeat: true) == .none)
        #expect(driver.keyUp(49, at: 3) == .stop)
    }

    @Test func hotkeyRoundTripsAndNamesItself() throws {
        #expect(try roundTripThroughJSON(controlOptionSpace) == controlOptionSpace)
        #expect(Hotkey.rightCommand.displayName == "Right ⌘")
        #expect(controlOptionSpace.displayName == "⌃⌥Space")
        #expect(SystemShortcuts.warning(for: Hotkey(keyCode: 49, modifiers: .maskCommand)) != nil)
        #expect(SystemShortcuts.warning(for: controlOptionSpace) == nil)
    }
}
