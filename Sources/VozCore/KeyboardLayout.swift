import Carbon.HIToolbox
import Foundation

public enum KeyboardLayout {
    private static let keyCount: UInt16 = 128

    public static func keyCode(producing character: String) -> UInt16? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> UInt16? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            return (0..<Self.keyCount).first { translate(keyCode: $0, layout: layout) == character }
        }
    }

    private static func translate(keyCode: UInt16, layout: UnsafePointer<UCKeyboardLayout>) -> String? {
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
