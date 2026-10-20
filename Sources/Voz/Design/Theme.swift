import AppKit
import SwiftUI

enum Theme {
    static let canvas = Color(light: 0xF6F4EF, dark: 0x161618)
    static let surface = Color(light: 0xFFFFFF, dark: 0x0E0E10)
    static let ink = Color(light: 0x141414, dark: 0xF2F0EB)
    static let inkSecondary = Color(light: 0x5F5C55, dark: 0xA5A29A)
    static let inkTertiary = Color(light: 0x7B7870, dark: 0x7F7C75)
    static let hairline = Color(light: 0x141414, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.09)
    static let selected = Color(light: 0xE9E6DF, dark: 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.09)
    static let accent = Color(light: 0x5163F9, dark: 0x6475FA)
    static let onInk = Color(light: 0xFFFFFF, dark: 0x141414)

    enum Radius {
        static let control: CGFloat = 8
        static let row: CGFloat = 10
        static let panel: CGFloat = 16
    }

    enum Spacing {
        static let item: CGFloat = 16
    }

    enum Motion {
        static let press = Animation.easeOut(duration: 0.12)
        static let hover = Animation.easeOut(duration: 0.15)
        static let section = Animation.easeOut(duration: 0.18)
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
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            Theme.isDark(appearance) ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension Font {
    static func display(_ size: CGFloat) -> Font {
        .custom("GeistPixel-Square", size: size)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .medium: .custom("Geist-Medium", size: size)
        case .semibold: .custom("Geist-SemiBold", size: size)
        default: .custom("Geist-Regular", size: size)
        }
    }

    static let meta = Font.ui(12)
}
