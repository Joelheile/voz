import AppKit
import SwiftUI

enum Theme {
    static let canvas = Color(light: 0xF2F2F4, dark: 0x1C1C1F)
    static let surface = Color(light: 0xFBFBFC, dark: 0x1E1E21)
    static let raised = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.17)
    static let group = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.62, darkAlpha: 0.05)
    static let ink = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let inkSecondary = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.56, darkAlpha: 0.6)
    static let inkTertiary = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.4, darkAlpha: 0.4)
    static let hairline = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
    static let selected = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.08)
    static let selectedStrong = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.11, darkAlpha: 0.16)
    static let accent = Color(light: 0x007AFF, dark: 0x0A84FF)
    static let recording = Color(light: 0xFF3B30, dark: 0xFF453A)
    static let success = Color(light: 0x28CD41, dark: 0x30D158)
    static let failure = Color(nsColor: .systemOrange)
    static let onInk = Color(light: 0xFFFFFF, dark: 0x141414)

    enum Radius {
        static let control: CGFloat = 8
        static let row: CGFloat = 10
        static let group: CGFloat = 12
        static let panel: CGFloat = 18
    }

    enum Spacing {
        static let item: CGFloat = 12
    }

    enum Size {
        static let row: CGFloat = 38
    }

    enum Motion {
        static let press = Animation.easeOut(duration: 0.12)
        static let hover = Animation.easeOut(duration: 0.15)
        static let section = Animation.easeOut(duration: 0.18)
        static let reorder = Animation.spring(duration: 0.22, bounce: 0)
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
        .custom("Geist-Medium", size: size)
    }

    static func wordmark(_ size: CGFloat) -> Font {
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
