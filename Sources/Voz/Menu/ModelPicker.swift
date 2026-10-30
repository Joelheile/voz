import SwiftUI

struct ModelOption: Hashable {
    let id: String
    let name: String
    let detail: String

    static func extensions(_ components: [HostComponent]) -> [ModelOption] {
        components.map { ModelOption(id: $0.id, name: $0.name, detail: "Extension") }
    }
}

struct ModelPicker: View {
    let title: String
    @Binding var selection: String
    let options: [ModelOption]
    @State private var expanded = false
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selected: ModelOption {
        options.first { $0.id == selection } ?? ModelOption(id: selection, name: selection, detail: "Not loaded")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: { header }
                .buttonStyle(.plain)
            if expanded {
                VStack(spacing: 2) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        ModelOptionRow(option: option, selected: option.id == selection, highlight: highlight) {
                            choose(option.id)
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: reduceMotion ? 0 : -4))
                                .animation(.spring(duration: 0.25, bounce: 0).delay(Double(index) * 0.03)),
                            removal: .opacity.animation(.easeOut(duration: 0.12))
                        ))
                    }
                }
                .padding(.horizontal, -6)
                .padding(.bottom, 8)
            }
        }
        .animation(Theme.Motion.section, value: expanded)
    }

    private func choose(_ id: String) {
        withAnimation(.spring(duration: 0.25, bounce: 0.15)) { selection = id }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            expanded = false
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Text("\(selected.name), \(selected.detail)")
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
            Spacer(minLength: 0)
            Icon(.chevronDown, size: 13)
                .foregroundStyle(Theme.inkTertiary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .animation(.spring(duration: 0.3, bounce: 0.2), value: expanded)
        }
        .frame(minHeight: Theme.Size.row)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct ModelOptionRow: View {
    let option: ModelOption
    let selected: Bool
    let highlight: Namespace.ID
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                ZStack {
                    if selected {
                        Icon(.check, size: 13)
                            .foregroundStyle(Theme.accent)
                            .popIn()
                    }
                }
                .frame(width: 14)
                Text(option.name)
                    .font(.ui(13, weight: selected ? .medium : .regular))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Text(option.detail)
                    .font(.meta)
                    .monospacedDigit()
                    .foregroundStyle(selected ? Theme.inkSecondary : Theme.inkTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.selected)
                        .matchedGeometryEffect(id: "selection", in: highlight)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.selected.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OptionPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

private struct OptionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}
