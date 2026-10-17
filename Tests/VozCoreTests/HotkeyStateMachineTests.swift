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

    func pointerDown() {
        machine.handle(.pointerDown)
    }
}

private let controlOptionSpace = Hotkey(keyCode: 49, modifiers: [.maskControl, .maskAlternate])
private let controlOptionFlags: CGEventFlags = [.maskControl, .maskAlternate]
private let rightOption = Hotkey(keyCode: 61, modifiers: .maskAlternate)
private let fn = Hotkey(keyCode: 63, modifiers: [])

@Suite struct TapModeTests {
    @Test func quickTapTriggersOnRelease() {
        let driver = Driver()
        #expect(driver.press(at: 0) == .none)
        #expect(driver.release(at: 0.1) == .toggle)
    }

    @Test func longHoldDoesNotTrigger() {
        let driver = Driver()
        driver.press(at: 0)
        #expect(driver.release(at: 2) == .none)
    }

    @Test func keyDownWhileHeldCancels() {
        let driver = Driver()
        driver.press(at: 0)
        #expect(driver.keyDown(8, flags: .maskCommand) == .none)
        #expect(driver.release(at: 0.2) == .none)
    }

    @Test func pointerDownWhileHeldCancels() {
        let driver = Driver()
        driver.press(at: 0)
        driver.pointerDown()
        #expect(driver.release(at: 0.2) == .none)
    }

    @Test func otherModifierWhileHeldCancels() {
        let driver = Driver()
        driver.press(at: 0)
        driver.press(at: 0.05, keyCode: 56, flags: [.maskCommand, .maskShift])
        #expect(driver.release(at: 0.2) == .none)
    }

    @Test func nextTapWorksAfterCancelledChord() {
        let driver = Driver()
        driver.press(at: 0)
        driver.keyDown(8, flags: .maskCommand)
        driver.release(at: 0.2)
        driver.press(at: 1)
        #expect(driver.release(at: 1.1) == .toggle)
    }

    @Test func otherModifierHeldBeforePressDoesNotArm() {
        let driver = Driver()
        #expect(driver.press(at: 0, flags: [.maskCommand, .maskShift]) == .none)
        #expect(driver.release(at: 0.1) == .none)
    }

    @Test func leftCommandIsIgnored() {
        let driver = Driver()
        driver.press(at: 0, keyCode: 55)
        #expect(driver.release(at: 0.1, keyCode: 55) == .none)
    }

    @Test func resetClearsPressedState() {
        let driver = Driver()
        driver.press(at: 0)
        driver.machine.reset()
        #expect(driver.release(at: 0.1) == .none)
    }

    @Test func releaseEventWithoutPressDoesNotArm() {
        let driver = Driver()
        #expect(driver.release(at: 0) == .none)
        #expect(driver.release(at: 0.1) == .none)
    }

    @Test func rightOptionTaps() {
        let driver = Driver(hotkey: rightOption)
        driver.press(at: 0, keyCode: 61, flags: .maskAlternate)
        #expect(driver.release(at: 0.1, keyCode: 61) == .toggle)
    }

    @Test func fnTapsWithFnFlag() {
        let driver = Driver(hotkey: fn)
        driver.press(at: 0, keyCode: 63, flags: .maskSecondaryFn)
        #expect(driver.release(at: 0.1, keyCode: 63) == .toggle)
    }

    @Test func fnIgnoredWhenAnotherModifierIsHeld() {
        let driver = Driver(hotkey: fn)
        #expect(driver.press(at: 0, keyCode: 63, flags: [.maskSecondaryFn, .maskShift]) == .none)
    }
}

@Suite struct ComboTests {
    @Test func comboTogglesOnKeyDown() {
        let driver = Driver(hotkey: controlOptionSpace)
        #expect(driver.keyDown(49, flags: controlOptionFlags) == .toggle)
        #expect(driver.keyDown(49, flags: .maskControl) == .none)
        #expect(driver.keyDown(8, flags: controlOptionFlags) == .none)
    }

    @Test func comboIgnoresAutoRepeat() {
        let driver = Driver(hotkey: controlOptionSpace)
        #expect(driver.keyDown(49, flags: controlOptionFlags) == .toggle)
        #expect(driver.keyDown(49, flags: controlOptionFlags, isRepeat: true) == .none)
    }

    @Test func comboKeyUpDoesNothingInTapMode() {
        let driver = Driver(hotkey: controlOptionSpace)
        driver.keyDown(49, flags: controlOptionFlags)
        #expect(driver.keyUp(49, at: 0.1) == .none)
    }

    @Test func singleNonModifierKeyWorks() {
        let driver = Driver(hotkey: Hotkey(keyCode: 96, modifiers: []))
        #expect(driver.keyDown(96, flags: []) == .toggle)
    }

    @Test func modifierFlagsChangedDoNotTriggerCombo() {
        let driver = Driver(hotkey: controlOptionSpace)
        #expect(driver.press(at: 0, keyCode: 59, flags: .maskControl) == .none)
        #expect(driver.release(at: 0.1, keyCode: 59) == .none)
    }
}

@Suite struct HoldModeTests {
    @Test func pressStartsRecording() {
        let driver = Driver(holdToTalk: true)
        #expect(driver.press(at: 0) == .start)
    }

    @Test func holdThenReleaseStops() {
        let driver = Driver(holdToTalk: true)
        driver.press(at: 0)
        driver.isRecording = true
        #expect(driver.release(at: 2) == .stop)
    }

    @Test func quickTapKeepsRecording() {
        let driver = Driver(holdToTalk: true)
        driver.press(at: 0)
        driver.isRecording = true
        #expect(driver.release(at: 0.2) == .none)
    }

    @Test func pressWhileRecordingStopsAndReleaseIsIgnored() {
        let driver = Driver(holdToTalk: true)
        driver.isRecording = true
        #expect(driver.press(at: 5) == .stop)
        #expect(driver.release(at: 8) == .none)
    }

    @Test func chordWhileHeldStopsOnRelease() {
        let driver = Driver(holdToTalk: true)
        driver.press(at: 0)
        driver.isRecording = true
        driver.keyDown(8, flags: .maskCommand)
        #expect(driver.release(at: 0.2) == .stop)
    }

    @Test func comboHoldStartsOnKeyDownAndStopsOnKeyUp() {
        let driver = Driver(hotkey: controlOptionSpace, holdToTalk: true)
        #expect(driver.keyDown(49, flags: controlOptionFlags, at: 0) == .start)
        driver.isRecording = true
        #expect(driver.keyDown(49, flags: controlOptionFlags, at: 0.5, isRepeat: true) == .none)
        #expect(driver.keyUp(49, at: 3) == .stop)
    }

    @Test func comboQuickTapKeepsRecording() {
        let driver = Driver(hotkey: controlOptionSpace, holdToTalk: true)
        driver.keyDown(49, flags: controlOptionFlags, at: 0)
        driver.isRecording = true
        #expect(driver.keyUp(49, at: 0.1) == .none)
    }

    @Test func comboPointerDownDoesNotStopHold() {
        let driver = Driver(hotkey: controlOptionSpace, holdToTalk: true)
        driver.keyDown(49, flags: controlOptionFlags, at: 0)
        driver.isRecording = true
        driver.pointerDown()
        #expect(driver.keyUp(49, at: 0.1) == .none)
    }

    @Test func configureResetsState() {
        let driver = Driver(holdToTalk: true)
        driver.press(at: 0)
        driver.machine.configure(hotkey: .rightCommand, holdToTalk: false)
        #expect(driver.release(at: 0.1) == .none)
    }
}
