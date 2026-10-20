import SwiftUI
import VozCore

struct SpeechModelPicker: View {
    @Binding var selection: SpeechModel
    var status: ModelStatus?
    @State private var expanded = false
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsStatus: Bool {
        guard let status, selection != .appleSpeech else { return false }
        if case .ready = status.state(for: selection) { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: { header }
                .buttonStyle(.plain)
            if expanded {
                VStack(spacing: 2) {
                    ForEach(Array(SpeechModel.allCases.enumerated()), id: \.element) { index, model in
                        SpeechModelOption(model: model, selected: model == selection, highlight: highlight) {
                            choose(model)
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

    private func choose(_ model: SpeechModel) {
        withAnimation(.spring(duration: 0.25, bounce: 0.15)) { selection = model }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            expanded = false
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Speech model").font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Text("\(selection.name), \(selection.size)")
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
            Spacer(minLength: 0)
            if showsStatus, let status {
                ModelStatusLabel(status: status, model: selection)
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .animation(.spring(duration: 0.3, bounce: 0.2), value: expanded)
        }
        .frame(minHeight: 40)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct SpeechModelOption: View {
    let model: SpeechModel
    let selected: Bool
    let highlight: Namespace.ID
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                ZStack {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .transition(.symbolEffect(.drawOn))
                    }
                }
                .frame(width: 14)
                Text(model.name)
                    .font(.ui(13, weight: selected ? .medium : .regular))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Text(model.size)
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
