import CoreGraphics
import Foundation

enum HotkeyInput: Sendable {
    case flagsChanged(keyCode: UInt16, flags: CGEventFlags, time: TimeInterval)
    case keyDown(keyCode: UInt16, flags: CGEventFlags, time: TimeInterval, isRepeat: Bool)
    case keyUp(keyCode: UInt16, time: TimeInterval)
    case pointerDown
}

enum HotkeyAction: Equatable, Sendable {
    case none
    case toggle
    case start
    case stop
}

struct HotkeyStateMachine: Sendable {
    static let defaultMaxTapDuration: TimeInterval = 0.5

    private(set) var hotkey: Hotkey
    private(set) var holdToTalk: Bool
    private let maxTapDuration: TimeInterval
    private var downSince: TimeInterval?
    private var chordDetected = false
    private var startedOnPress = false

    init(
        hotkey: Hotkey = .rightCommand,
        holdToTalk: Bool = false,
        maxTapDuration: TimeInterval = defaultMaxTapDuration
    ) {
        self.hotkey = hotkey
        self.holdToTalk = holdToTalk
        self.maxTapDuration = maxTapDuration
    }

    mutating func configure(hotkey: Hotkey, holdToTalk: Bool) {
        self.hotkey = hotkey
        self.holdToTalk = holdToTalk
        reset()
    }

    mutating func reset() {
        downSince = nil
        chordDetected = false
        startedOnPress = false
    }

    mutating func handle(_ input: HotkeyInput, isRecording: Bool = false) -> HotkeyAction {
        switch input {
        case let .flagsChanged(keyCode, flags, time):
            return handleFlagsChanged(keyCode: keyCode, flags: flags, time: time, isRecording: isRecording)
        case let .keyDown(keyCode, flags, time, isRepeat):
            return handleKeyDown(keyCode: keyCode, flags: flags, time: time, isRepeat: isRepeat, isRecording: isRecording)
        case let .keyUp(keyCode, time):
            guard !hotkey.isModifierOnly, keyCode == hotkey.keyCode else { return .none }
            return release(at: time)
        case .pointerDown:
            markChordIfDown()
            return .none
        }
    }

    private mutating func handleFlagsChanged(
        keyCode: UInt16, flags: CGEventFlags, time: TimeInterval, isRecording: Bool
    ) -> HotkeyAction {
        guard let ownFlag = hotkey.ownModifierFlag else { return .none }
        if hotkey.isChord { return handleChordFlags(flags: flags, time: time, isRecording: isRecording) }
        guard keyCode == hotkey.keyCode else {
            markChordIfDown()
            return .none
        }
        if downSince != nil { return release(at: time) }
        guard flags.contains(ownFlag), flags.intersection(hotkey.matchedModifiers) == hotkey.modifiers else {
            return .none
        }
        return press(at: time, isRecording: isRecording)
    }

    private mutating func handleChordFlags(flags: CGEventFlags, time: TimeInterval, isRecording: Bool) -> HotkeyAction {
        let held = flags.intersection(hotkey.matchedModifiers)
        if downSince != nil {
            guard held.isSuperset(of: hotkey.modifiers) else { return release(at: time) }
            if held != hotkey.modifiers { chordDetected = true }
            return .none
        }
        guard held == hotkey.modifiers else { return .none }
        return press(at: time, isRecording: isRecording)
    }

    private mutating func handleKeyDown(
        keyCode: UInt16, flags: CGEventFlags, time: TimeInterval, isRepeat: Bool, isRecording: Bool
    ) -> HotkeyAction {
        guard !hotkey.isModifierOnly else {
            markChordIfDown()
            return .none
        }
        guard !isRepeat, keyCode == hotkey.keyCode,
              flags.intersection(Hotkey.relevantModifiers) == hotkey.modifiers
        else { return .none }
        return press(at: time, isRecording: isRecording)
    }

    private mutating func press(at time: TimeInterval, isRecording: Bool) -> HotkeyAction {
        downSince = time
        chordDetected = false
        startedOnPress = false
        guard holdToTalk else { return hotkey.isModifierOnly ? .none : .toggle }
        if isRecording { return .stop }
        startedOnPress = true
        return .start
    }

    private mutating func release(at time: TimeInterval) -> HotkeyAction {
        guard let since = downSince else { return .none }
        let wasChord = chordDetected
        let didStart = startedOnPress
        reset()
        let wasQuick = time - since <= maxTapDuration
        if holdToTalk {
            return didStart && (wasChord || !wasQuick) ? .stop : .none
        }
        return hotkey.isModifierOnly && !wasChord && wasQuick ? .toggle : .none
    }

    private mutating func markChordIfDown() {
        if downSince != nil, hotkey.isModifierOnly { chordDetected = true }
    }
}
