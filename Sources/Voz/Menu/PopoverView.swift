import SwiftUI
import VozCore

struct PopoverView: View {
    static let width: CGFloat = 340

    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.item) {
            header
            statusDetail
            StatNumber(value: model.wordsThisWeek, unit: "words this week", size: 32)
            TranscriptList(model: model)
            footer
        }
        .padding(Theme.Spacing.item)
        .frame(width: Self.width)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.hairline))
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.status.title)
                    .font(.display(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(model.hint)
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            PopoverGlyph(status: model.status)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch model.status {
        case let .loadingModel(_, progress):
            if let progress {
                ProgressView(value: progress).progressViewStyle(.linear).tint(Theme.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Theme.accent)
            }
        case let .permissionNeeded(fix):
            Button(fix.buttonTitle) { model.actions.fixPermission(fix) }
                .buttonStyle(.pill(.accent, height: 34))
        default:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button("Open voz", action: model.actions.openApp)
                .buttonStyle(.pill(.ink, height: 34))
            Button("Retry last", action: model.actions.retry)
                .buttonStyle(QuietTextButtonStyle())
                .disabled(!model.canRetry)
            Spacer(minLength: 0)
            IconButton(symbol: "gearshape", help: "Settings", action: model.actions.openSettings)
            IconButton(symbol: "power", help: "Quit voz", action: model.actions.quit)
        }
    }
}

private struct QuietTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
    }
}

private struct TranscriptList: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(spacing: 0) {
            if model.transcripts.isEmpty {
                Text("Nothing dictated yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            ForEach(Array(model.transcripts.enumerated()), id: \.element.id) { index, record in
                if index > 0 { RowDivider() }
                TranscriptRow(record: record, copied: model.copiedID == record.id) { model.copy(record) }
            }
        }
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }
}

private struct TranscriptRow: View {
    let record: TranscriptRecord
    let copied: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(record.finalText.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(hovering ? Theme.selected.opacity(0.6) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(record.finalText)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
        .animation(Theme.Motion.hover, value: copied)
    }

    @ViewBuilder
    private var trailing: some View {
        if copied {
            Text("Copied")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .transition(.opacity)
        } else {
            Text(record.createdAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.meta)
                .foregroundStyle(Theme.inkTertiary)
                .transition(.opacity)
        }
    }
}

private struct PopoverGlyph: View {
    let status: PopoverStatus

    var body: some View {
        switch status {
        case .recording:
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                LevelBarsMark(heights: (0..<4).map { 0.45 + 0.5 * abs(sin(time * 3 + Double($0))) }, height: 22, barWidth: 3.5, spacing: 3, color: Theme.accent)
            }
        case .transcribing, .loadingModel:
            LevelBarsMark(heights: [0.3, 0.3, 0.3, 0.3], height: 22, barWidth: 3.5, spacing: 3, color: Theme.inkTertiary)
        case .permissionNeeded, .modelFailed:
            LevelBarsMark(heights: [0.45, 0.8, 1, 0.62], height: 22, barWidth: 3.5, spacing: 3, color: Theme.inkTertiary)
        case .ready:
            LevelBarsMark(heights: [0.45, 0.8, 1, 0.62], height: 22, barWidth: 3.5, spacing: 3, color: Theme.ink)
        }
    }
}
