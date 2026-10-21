import SwiftUI
import VozCore

struct SpeechModelPicker: View {
    @Binding var selection: SpeechModel
    var status: ModelStatus?
    var showsTitle = true
    @Namespace private var highlight

    private var showsStatus: Bool {
        guard let status, selection != .appleSpeech else { return false }
        if case .ready = status.state(for: selection) { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle { title }
            HStack(spacing: 6) {
                ForEach(SpeechModel.allCases, id: \.self) { model in
                    SpeechModelCard(model: model, selected: model == selection, highlight: highlight) {
                        withAnimation(.spring(duration: 0.3, bounce: 0.15)) { selection = model }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, showsTitle ? 10 : 0)
    }

    private var title: some View {
        HStack(spacing: 12) {
            Text("Speech model").font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            if showsStatus, let status {
                ModelStatusLabel(status: status, model: selection)
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct SpeechModelCard: View {
    let model: SpeechModel
    let selected: Bool
    let highlight: Namespace.ID
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.family)
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkTertiary)
                    Text(model.name)
                        .font(.ui(13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(model.languages)
                        .font(.ui(11))
                        .padding(.top, 2)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                RowDivider()
                VStack(alignment: .leading, spacing: 3) {
                    Metric(value: model.errorRate.formatted(.percent.scale(1).precision(.fractionLength(1)).locale(Locale(identifier: "en_US"))), label: "errors")
                    Metric(value: "\(model.speedFactor)×", label: "speed")
                    Metric(value: model.size, label: nil)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                        .padding(8)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .background { background }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.pressable(0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.family) \(model.name), \(model.languages), \(model.errorRate) percent word errors, \(model.speedFactor) times real time, \(model.size)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        ZStack {
            shape
                .fill(hovering && !selected ? Theme.selected.opacity(0.5) : .clear)
                .strokeBorder(Theme.hairline)
            if selected {
                shape
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .matchedGeometryEffect(id: "selection", in: highlight)
            }
        }
    }
}

private struct Metric: View {
    let value: String
    let label: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.ui(12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            if let label {
                Text(label)
                    .font(.ui(11))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .lineLimit(1)
    }
}
