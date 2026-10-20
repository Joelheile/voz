import SwiftUI
import VozCore

struct IndicatorPicker: View {
    @Binding var selection: IndicatorStyle

    var body: some View {
        HStack(spacing: 8) {
            ForEach(IndicatorStyle.allCases, id: \.self) { style in
                IndicatorTile(style: style, selected: selection == style) { selection = style }
            }
        }
    }
}

private struct IndicatorTile: View {
    let style: IndicatorStyle
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                IndicatorMiniature(style: style)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Theme.hairline, lineWidth: selected ? 2 : 1)
                    )
                Text(style.title)
                    .font(.ui(12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.hover, value: selected)
    }
}

private struct IndicatorMiniature: View {
    let style: IndicatorStyle

    var body: some View {
        VStack(spacing: 0) {
            shape
                .frame(width: 52, height: 16)
                .overlay(alignment: .trailing) { MiniBars().padding(.trailing, 9) }
                .padding(.top, style == .notch ? 0 : 6)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var shape: some View {
        switch style {
        case .notch:
            UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7, style: .continuous).fill(.black)
        case .pill:
            Capsule().fill(.black)
        }
    }
}

private struct MiniBars: View {
    private static let phases: [Double] = [0, 1.3, 2.4, 0.7]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 1.5) {
                ForEach(Self.phases.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white)
                        .frame(width: 2, height: 3 + 5 * (0.5 + 0.5 * sin(time * 5 + Self.phases[index])))
                }
            }
            .frame(height: 8)
        }
    }
}
