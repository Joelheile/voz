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

struct PageBar<Trailing: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 4) {
            IconButton(icon: .chevronLeft, help: "Back", action: back)
                .keyboardShortcut("[", modifiers: .command)
            Text(title)
                .font(.display(17))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, -6)
    }
}

extension PageBar where Trailing == EmptyView {
    init(title: String, back: @escaping () -> Void) {
        self.init(title: title, back: back) { EmptyView() }
    }
}

struct PageNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.meta)
            .lineSpacing(2)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PanelGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title { SectionLabel(text: title) }
            VStack(spacing: 0) { content }
        }
    }
}

struct PanelRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.meta)
                        .lineSpacing(2)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .frame(minHeight: Theme.Size.row)
        .padding(.vertical, 4)
    }
}

struct LinkRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        ActionRow(title: title, value: value, action: action) { hovering in
            Icon(.chevronRight, size: 13)
                .foregroundStyle(hovering ? Theme.ink : Theme.inkTertiary)
        }
    }
}

struct ActionRow<Trailing: View>: View {
    let title: String
    let value: String
    let action: () -> Void
    @ViewBuilder var trailing: (Bool) -> Trailing
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Text(value).font(.meta).foregroundStyle(Theme.inkSecondary)
                trailing(hovering)
            }
            .frame(minHeight: Theme.Size.row)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

extension ActionRow where Trailing == EmptyView {
    init(title: String, value: String, action: @escaping () -> Void) {
        self.init(title: title, value: value, action: action) { _ in EmptyView() }
    }
}

struct CappedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maxHeight))
    }
}

struct TabBar<Tab: Hashable & RawRepresentable<String>>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                Button { selection = tab } label: {
                    Text(tab.rawValue)
                        .font(.ui(12, weight: .medium))
                        .foregroundStyle(tab == selection ? Theme.ink : Theme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background {
                            if tab == selection {
                                RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous)
                                    .fill(Theme.raised)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.selected, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .animation(.spring(duration: 0.25, bounce: 0), value: selection)
    }
}

struct AccentSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Theme.accent : Theme.selected)
                .frame(width: 30, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(duration: 0.2, bounce: 0), value: configuration.isOn)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == AccentSwitchStyle {
    static var accentSwitch: AccentSwitchStyle { AccentSwitchStyle() }
}
