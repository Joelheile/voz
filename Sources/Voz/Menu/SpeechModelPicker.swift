import SwiftUI
import VozCore

struct SpeechModelPicker: View {
    @Binding var selection: SpeechModel
    var status: ModelStatus?
    @State private var expanded = false

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
                    ForEach(SpeechModel.allCases, id: \.self) { model in
                        SpeechModelOption(model: model, selected: model == selection) {
                            selection = model
                            expanded = false
                        }
                    }
                }
                .padding(.horizontal, -6)
                .padding(.bottom, 8)
            }
        }
        .animation(Theme.Motion.section, value: expanded)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Speech model").font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(selection.label).font(.ui(11.5)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsStatus, let status {
                ModelStatusLabel(status: status, model: selection)
                    .font(.ui(12.5))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .frame(minHeight: 40)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct SpeechModelOption: View {
    let model: SpeechModel
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0)
                Text(model.label)
                    .font(.ui(13))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(hovering ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}
