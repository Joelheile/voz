import SwiftUI

struct Card<Content: View>: View {
    var fill: Color = Theme.surface
    var padding: CGFloat = Theme.Spacing.block
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.hairline))
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.display(40, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.inkSecondary)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.display(22, weight: .semibold))
            .foregroundStyle(Theme.ink)
    }
}

struct StatNumber: View {
    let value: Int
    let unit: String
    var size: CGFloat = 44
    var color: Color = Theme.ink
    var unitColor: Color = Theme.inkSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value, format: .number)
                .font(.display(size))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: max(14, size * 0.34)))
                .foregroundStyle(unitColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .animation(.smooth, value: value)
    }
}

struct StatText: View {
    let value: String
    let unit: String
    var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.display(size))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: max(14, size * 0.34)))
                .foregroundStyle(Theme.inkSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .animation(.smooth, value: value)
    }
}

struct SerifHeadline: View {
    let lead: String
    let accented: String
    var size: CGFloat = 34
    var color: Color = Theme.ink
    var accentColor: Color = Theme.accent

    var body: some View {
        Text(lead + " ").font(.display(size)).foregroundStyle(color)
            + Text(accented).font(.display(size)).italic().foregroundStyle(accentColor)
    }
}

enum PillKind {
    case ink
    case accent
    case light
    case quiet

    var fill: Color {
        switch self {
        case .ink: Theme.ink
        case .accent: Theme.accent
        case .light: .white
        case .quiet: Theme.selected
        }
    }

    var text: Color {
        switch self {
        case .ink: Theme.onInk
        case .accent: .white
        case .light: .black
        case .quiet: Theme.ink
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var kind: PillKind = .ink
    var height: CGFloat = 36
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(kind.text)
            .padding(.horizontal, height * 0.55)
            .frame(height: height)
            .background(kind.fill, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillKind = .ink, height: CGFloat = 36) -> PillButtonStyle {
        PillButtonStyle(kind: kind, height: height)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? Theme.ink : Theme.inkSecondary)
                .frame(width: 30, height: 30)
                .background(hovering ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.rowTitle).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.meta)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.vertical, 14)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

struct EmptyNote: View {
    let symbol: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.inkTertiary)
            Text(title).font(.display(20, weight: .semibold)).foregroundStyle(Theme.ink)
            if let detail {
                Text(detail).font(.meta).foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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

struct LevelBarsMark: View {
    var heights: [CGFloat] = [0.45, 0.8, 1, 0.62]
    var height: CGFloat = 40
    var barWidth: CGFloat = 8
    var spacing: CGFloat = 6
    var color: Color = .white
    var accentIndex: Int?
    var accent: Color = Theme.accentOnBlack

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, fraction in
                Capsule()
                    .fill(index == accentIndex ? accent : color)
                    .frame(width: barWidth, height: height * fraction)
            }
        }
        .frame(height: height)
    }
}

struct SettingGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: title)
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 { RowDivider() }
                        rows[index]
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.hairline))
            }
        }
    }
}
