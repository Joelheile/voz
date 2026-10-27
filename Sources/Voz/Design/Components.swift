import LucideSwift
import SwiftUI

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.meta)
            .foregroundStyle(Theme.inkSecondary)
    }
}

enum PillKind {
    case ink
    case accent
    case quiet

    var fill: Color {
        switch self {
        case .ink: Theme.ink
        case .accent: Theme.accent
        case .quiet: Theme.selected
        }
    }

    var text: Color {
        switch self {
        case .ink: Theme.onInk
        case .accent: .white
        case .quiet: Theme.ink
        }
    }
}

enum PillSize {
    case small
    case regular

    var height: CGFloat {
        switch self {
        case .small: 28
        case .regular: 34
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var kind: PillKind = .ink
    var size: PillSize = .regular
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(size == .small ? 12 : 13, weight: .medium))
            .foregroundStyle(kind.text)
            .padding(.horizontal, size.height * 0.5)
            .frame(height: size.height)
            .background(kind.fill, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillKind = .ink, _ size: PillSize = .regular) -> PillButtonStyle {
        PillButtonStyle(kind: kind, size: size)
    }
}

struct PressableButtonStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static func pressable(_ scale: CGFloat) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale)
    }
}

struct IconButton: View {
    let icon: LucideIconName
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 14)
                .foregroundStyle(hovering ? Theme.ink : Theme.inkSecondary)
                .frame(width: 30, height: 30)
                .background(hovering ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(0.92))
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

extension View {
    func fieldBackground(_ size: PillSize = .regular) -> some View {
        padding(.horizontal, 12)
            .frame(height: size.height)
            .background(Theme.canvas, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

struct SearchField: View {
    @Binding var text: String
    let prompt: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Icon(.search)
                .foregroundStyle(Theme.inkTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.ui(13))
                .foregroundStyle(Theme.ink)
                .focused(focused)
        }
        .frame(maxWidth: .infinity)
        .fieldBackground()
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
