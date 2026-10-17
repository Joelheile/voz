import Foundation

public struct OutputSettings: Equatable, Sendable {
    public var copyToClipboard = true
    public var pasteIntoActiveApp = true

    public init() {}

    public var needsClipboardRestore: Bool {
        pasteIntoActiveApp && !copyToClipboard
    }
}

public enum ClipboardRestoreGuard {
    public static let delay: TimeInterval = 0.25

    public static func shouldRestore(changeCountAtWrite: Int, currentChangeCount: Int) -> Bool {
        changeCountAtWrite == currentChangeCount
    }
}
