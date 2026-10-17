import AppKit
import SwiftUI

enum Theme {
    static let canvas = Color(light: 0xF6F4EF, dark: 0x161618)
    static let surface = Color(light: 0xFFFFFF, dark: 0x0E0E10)
    static let ink = Color(light: 0x141414, dark: 0xF2F0EB)
    static let inkSecondary = Color(light: 0x5F5C55, dark: 0xA5A29A)
    static let inkTertiary = Color(light: 0x7B7870, dark: 0x7F7C75)
    static let hairline = Color(light: 0x141414, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.09)
    static let hover = Color(light: 0xF7F5F1, dark: 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.04)
    static let selected = Color(light: 0xE9E6DF, dark: 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.09)
    static let hero = Color(light: 0x0D0D0E, dark: 0x26262A)
    static let accent = Color(light: 0xDC3E42, dark: 0xF0555A)
    static let accentOnBlack = Color(hex: 0xF0555A)
    static let onInk = Color(light: 0xFFFFFF, dark: 0x141414)

    enum Radius {
        static let control: CGFloat = 8
        static let row: CGFloat = 12
        static let card: CGFloat = 16
        static let panel: CGFloat = 22
    }

    enum Spacing {
        static let page: CGFloat = 44
        static let section: CGFloat = 32
        static let block: CGFloat = 24
        static let item: CGFloat = 16
        static let tight: CGFloat = 8
    }

    enum Motion {
        static let press = Animation.easeOut(duration: 0.12)
        static let hover = Animation.easeOut(duration: 0.15)
        static let section = Animation.easeOut(duration: 0.18)
    }

    static let accentNSColor = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(hex: 0xF0555A) : NSColor(hex: 0xDC3E42)
    }

    static let canvasNSColor = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(hex: 0x161618) : NSColor(hex: 0xF6F4EF)
    }

    fileprivate static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            Theme.isDark(appearance) ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let body14 = Font.system(size: 14)
    static let rowTitle = Font.system(size: 14, weight: .medium)
    static let meta = Font.system(size: 12.5)
}
