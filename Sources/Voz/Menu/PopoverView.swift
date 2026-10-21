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
    let catalog: ExtensionCatalog
}

struct PopoverView: View {
    static let width: CGFloat = 360
    static let shadowInset: CGFloat = 28

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
            .fixedSize(horizontal: false, vertical: true)
            .compositingGroup()
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            .padding(Self.shadowInset)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { model.actions.resize($0) }
            .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var page: some View {
        if model.needsSetup {
            SetupPage(model: sources.setup, settings: sources.settings, history: sources.history, finish: model.actions.finishSetup)
        } else {
            switch model.page {
            case .home:
                HomePage(model: model, history: sources.history, settings: sources.settings)
            case .settings:
                SettingsPage(model: model, settings: sources.settings, status: sources.modelStatus, vocabulary: sources.vocabulary, catalog: sources.catalog)
            case .dictionary:
                DictionaryPage(model: sources.vocabulary, back: model.goBack)
            case .insights:
                InsightsPage(model: sources.stats, back: model.goBack)
            case .extensions:
                ExtensionsPage(model: sources.extensions, catalog: sources.catalog, back: model.goBack)
            case .cleanupPrompt:
                CleanupPromptPage(settings: sources.settings, back: model.goBack)
            case .cleanupSteps:
                CleanupStepsPage(settings: sources.settings, catalog: sources.catalog, back: model.goBack)
            }
        }
    }
}

private struct HomePage: View {
    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 38

    @ObservedObject var model: PopoverModel
    @ObservedObject var history: HistoryModel
    @ObservedObject var settings: AppSettings
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !history.query.isEmpty }
    private var showsSearch: Bool { isSearching || history.records.count > Self.visibleRows }
    private var records: [TranscriptRecord] {
        isSearching ? history.records : Array(history.records.prefix(Self.visibleRows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                header
                statusDetail
            }
            if showsSearch {
                SearchField(text: $history.query, prompt: "Search transcripts", focused: $searchFocused)
                    .onSubmit(copyFirstResult)
            }
            transcripts
            footer
        }
        .onAppear { searchFocused = showsSearch }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if model.status == .recording { RecordingMark() }
                Text(model.status.title)
                    .font(.display(17))
                    .foregroundStyle(Theme.ink)
            }
            Text(model.hint)
                .font(.meta)
                .lineSpacing(2)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
                .font(.ui(13))
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            IconButton(symbol: "chart.bar", help: "Insights") { model.page = .insights }
            IconButton(symbol: "puzzlepiece.extension", help: "Extensions") { model.page = .extensions }
            IconButton(symbol: "gearshape", help: "Settings") { model.page = .settings }
                .keyboardShortcut(",", modifiers: .command)
            IconButton(symbol: "power", help: "Quit Voz", action: model.actions.quit)
        }
        .padding(.trailing, -8)
    }

    private func copyFirstResult() {
        guard let first = records.first else { return }
        model.copy(first)
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
                    .font(.ui(13))
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
        .buttonStyle(.pressable(0.98))
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
                .font(.ui(12, weight: .semibold))
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

private struct RecordingMark: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing ? 1.35 : 1)
            .opacity(pulsing ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(), value: pulsing)
            .onAppear { pulsing = true }
    }
}
