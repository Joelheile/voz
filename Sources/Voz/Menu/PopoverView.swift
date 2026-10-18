import SwiftUI
import VozCore

struct PopoverSources {
    let settings: AppSettings
    let modelStatus: ModelStatus
    let history: HistoryModel
    let stats: StatsModel
    let vocabulary: VocabularyModel
    let setup: SetupModel
    let extensions: ExtensionsModel
}

struct PopoverView: View {
    static let width: CGFloat = 360

    @ObservedObject var model: PopoverModel
    let sources: PopoverSources

    var body: some View {
        page
            .id(model.needsSetup ? nil : model.page)
            .transition(.opacity)
            .padding(Theme.Spacing.item)
            .frame(width: Self.width)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.hairline))
            .toggleStyle(.switch)
            .animation(Theme.Motion.section, value: model.page)
    }

    @ViewBuilder
    private var page: some View {
        if model.needsSetup {
            SetupPage(model: sources.setup, settings: sources.settings, finish: model.actions.finishSetup)
        } else {
            switch model.page {
            case .home:
                HomePage(model: model, history: sources.history, stats: sources.stats, settings: sources.settings)
            case .settings:
                SettingsPage(model: model, settings: sources.settings, status: sources.modelStatus, vocabulary: sources.vocabulary)
            case .dictionary:
                DictionaryPage(model: sources.vocabulary, back: model.goBack)
            case .insights:
                InsightsPage(model: sources.stats, back: model.goBack)
            case .extensions:
                ExtensionsPage(model: sources.extensions, back: model.goBack)
            case .cleanupPrompt:
                CleanupPromptPage(settings: sources.settings, back: model.goBack)
            }
        }
    }
}

private struct HomePage: View {
    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 38

    @ObservedObject var model: PopoverModel
    @ObservedObject var history: HistoryModel
    @ObservedObject var stats: StatsModel
    @ObservedObject var settings: AppSettings
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !history.query.isEmpty }
    private var showsSearch: Bool { isSearching || history.records.count > Self.visibleRows }
    private var records: [TranscriptRecord] {
        isSearching ? history.records : Array(history.records.prefix(Self.visibleRows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusDetail
            if showsSearch {
                SearchField(text: $history.query, prompt: "Search transcripts", focused: $searchFocused)
                    .onSubmit(copyFirstResult)
            }
            transcripts
            StatsLine(stats: stats.stats) { model.page = .insights }
            RowDivider()
            footer
        }
        .onAppear { searchFocused = showsSearch }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusMark(status: model.status)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status.title)
                    .font(.display(20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(model.hint)
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch model.status {
        case let .loadingModel(_, progress):
            ProgressView(value: progress).progressViewStyle(.linear)
        case let .permissionNeeded(fix):
            Button(fix.buttonTitle) { model.actions.fixPermission(fix) }
                .buttonStyle(.pill(.accent, height: 32))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var transcripts: some View {
        if records.isEmpty {
            Text(isSearching ? "No matching transcripts" : "Your transcripts appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        } else {
            CappedScrollView(maxHeight: CGFloat(Self.visibleRows) * Self.rowHeight) {
                VStack(spacing: 0) {
                    ForEach(records) { record in
                        TranscriptRow(
                            record: record,
                            height: Self.rowHeight,
                            copied: model.copiedID == record.id,
                            copy: { model.copy(record) },
                            delete: { history.delete(record) }
                        )
                    }
                }
            }
            .padding(.horizontal, -8)
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            IconButton(symbol: "arrow.counterclockwise", help: "Retry last recording", action: model.actions.retry)
                .disabled(!model.canRetry)
                .opacity(model.canRetry ? 1 : 0.35)
            IconButton(symbol: "puzzlepiece.extension", help: "Extensions") { model.page = .extensions }
            IconButton(symbol: "gearshape", help: "Settings") { model.page = .settings }
                .keyboardShortcut(",", modifiers: .command)
            IconButton(symbol: "power", help: "Quit voz", action: model.actions.quit)
        }
    }

    private func copyFirstResult() {
        guard let first = records.first else { return }
        model.copy(first)
    }
}

private struct StatsLine: View {
    let stats: UsageStats
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Text(summary)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Theme.ink : Theme.inkTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Insights")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }

    private var summary: String {
        var parts = ["\(stats.wordsThisWeek.formatted()) words this week"]
        if let pace = stats.averageWordsPerMinute { parts.append("\(Int(pace.rounded())) wpm") }
        if stats.currentStreak > 1 { parts.append("\(stats.currentStreak)-day streak") }
        return parts.joined(separator: ", ")
    }
}

private struct TranscriptRow: View {
    let record: TranscriptRecord
    let height: CGFloat
    let copied: Bool
    let copy: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 10) {
                Text(record.finalText.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 8)
            .frame(height: height)
            .background(hovering ? Theme.selected.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(record.finalText)
        .contextMenu {
            Button("Copy", action: copy)
            Button("Delete", role: .destructive, action: delete)
        }
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
        .animation(Theme.Motion.hover, value: copied)
    }

    @ViewBuilder
    private var trailing: some View {
        if copied {
            Label("Copied", systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .transition(.opacity)
        } else if hovering {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .transition(.opacity)
        } else {
            Text(record.createdAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.meta)
                .foregroundStyle(Theme.inkTertiary)
                .transition(.opacity)
        }
    }
}

private struct StatusMark: View {
    let status: PopoverStatus
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .scaleEffect(isRecording && pulsing ? 1.35 : 1)
            .opacity(isRecording && pulsing ? 0.6 : 1)
            .animation(isRecording ? .easeInOut(duration: 0.7).repeatForever() : .default, value: pulsing)
            .onChange(of: isRecording, initial: true) { pulsing = isRecording }
    }

    private var isRecording: Bool { status == .recording }

    private var color: Color {
        switch status {
        case .ready, .recording: Theme.accent
        case .transcribing, .loadingModel: Theme.inkTertiary
        case .permissionNeeded, .modelFailed: Color(nsColor: .systemOrange)
        }
    }
}
