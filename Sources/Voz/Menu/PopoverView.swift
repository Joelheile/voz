import SwiftUI

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
            .padding(Theme.Spacing.item)
            .frame(width: Self.width)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.hairline))
            .toggleStyle(.switch)
            .tint(Theme.accent)
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
            SetupPage(model: sources.setup, settings: sources.settings, history: sources.history, status: model.status, retryModel: model.actions.retryModel, finish: model.actions.finishSetup)
        } else {
            switch model.page {
            case .home:
                HomePage(model: model, history: sources.history, catalog: sources.catalog, extensions: sources.extensions)
            case .settings:
                SettingsPage(model: model, settings: sources.settings, status: sources.modelStatus, vocabulary: sources.vocabulary, catalog: sources.catalog)
            case .dictionary:
                DictionaryPage(model: sources.vocabulary, back: model.goBack)
            case .insights:
                InsightsPage(model: sources.stats, settings: sources.settings, back: model.goBack)
            case .extensions:
                ExtensionsPage(model: sources.extensions, catalog: sources.catalog, settings: sources.settings, back: model.goBack)
            case .cleanupPrompt:
                CleanupPromptPage(settings: sources.settings, back: model.goBack)
            case .cleanupSteps:
                CleanupStepsPage(settings: sources.settings, catalog: sources.catalog, back: model.goBack)
            case .speechModel:
                SpeechModelPage(settings: sources.settings, status: sources.modelStatus, catalog: sources.catalog, back: model.goBack)
            case .whatsNew:
                WhatsNewPage(releases: Changelog.bundled, back: model.goBack)
            }
        }
    }
}

private struct HomePage: View {
    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 40

    @ObservedObject var model: PopoverModel
    @ObservedObject var history: HistoryModel
    @ObservedObject var catalog: ExtensionCatalog
    @ObservedObject var extensions: ExtensionsModel
    @FocusState private var searchFocused: Bool
    @State private var selectedID: UUID?

    private var records: [TranscriptRecord] { history.records }
    private var isSearching: Bool { !history.query.isEmpty }
    private var showsSearch: Bool { isSearching || !records.isEmpty }

    private var needsAttention: Bool {
        switch model.status {
        case .loadingModel, .modelFailed, .permissionNeeded: true
        default: false
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                header(proxy: proxy)
                if needsAttention { notice }
                transcripts
                ForEach(catalog.activities, id: \.id, content: activityRow)
                footer
            }
        }
        .onAppear { searchFocused = showsSearch }
        .onChange(of: history.query) { selectedID = nil }
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.hint.isEmpty {
                Text(model.hint)
                    .font(.meta)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            statusDetail
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch model.status {
        case let .loadingModel(_, progress?):
            ProgressView(value: progress).progressViewStyle(.linear)
        case .loadingModel:
            IndeterminateBar()
        case let .permissionNeeded(fix):
            Button(fix.buttonTitle) { model.actions.fixPermission(fix) }
                .buttonStyle(.pill(.accent, .regular))
        case .modelFailed:
            Button("Try again", action: model.actions.retryModel)
                .buttonStyle(.pill(.accent, .regular))
        default:
            EmptyView()
        }
    }

    private func header(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            if showsSearch {
                search(proxy: proxy)
            } else {
                Text("Voz").font(.wordmark(17)).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            status
        }
        .animation(Theme.Motion.section, value: model.status)
    }

    private func search(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            Icon(.search, size: 14)
                .foregroundStyle(Theme.inkTertiary)
            TextField("Search transcripts", text: $history.query)
                .textFieldStyle(.plain)
                .font(.ui(13))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
                .focusEffectDisabled()
            if isSearching {
                Text(resultCount)
                    .font(.meta)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.selected, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .animation(Theme.Motion.hover, value: isSearching)
        .onSubmit(copySelection)
        .onKeyPress(.downArrow) { moveSelection(by: 1, proxy: proxy) }
        .onKeyPress(.upArrow) { moveSelection(by: -1, proxy: proxy) }
        .onKeyPress(.escape) {
            guard isSearching else { return .ignored }
            history.query = ""
            return .handled
        }
    }

    @ViewBuilder
    private var transcripts: some View {
        if records.isEmpty {
            emptyState
        } else {
            TimelineView(.everyMinute) { context in
                CappedScrollView(maxHeight: CGFloat(Self.visibleRows) * Self.rowHeight) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            if let heading = heading(at: index, now: context.date) {
                                DayHeading(text: heading)
                            }
                            row(for: record, now: context.date)
                        }
                    }
                    .animation(isSearching ? nil : Theme.Motion.reorder, value: records.map(\.id))
                }
            }
            .padding(.horizontal, -8)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isSearching {
                Text("No matching transcripts")
                    .foregroundStyle(Theme.inkTertiary)
            } else {
                if !needsAttention, !model.hint.isEmpty {
                    Text(model.hint).foregroundStyle(Theme.ink)
                }
                Text("Your transcripts appear here.")
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .font(.ui(13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(at index: Int, now: Date) -> String? {
        guard !isSearching, let heading = RecentTime.heading(for: records[index].createdAt, now: now) else { return nil }
        guard index > 0 else { return heading }
        return RecentTime.heading(for: records[index - 1].createdAt, now: now) == heading ? nil : heading
    }

    private func row(for record: TranscriptRecord, now: Date) -> some View {
        TranscriptRow(
            record: record,
            query: history.query,
            time: RecentTime.label(for: record.createdAt, now: now),
            height: Self.rowHeight,
            selected: selectedID == record.id,
            copied: model.copiedID == record.id,
            copy: { model.copy(record) },
            delete: { history.delete(record) },
            hover: { hovering in
                if hovering {
                    selectedID = record.id
                } else if selectedID == record.id {
                    selectedID = nil
                }
            }
        )
        .id(record.id)
    }

    private func activityRow(_ activity: ExtensionActivity) -> some View {
        HStack(spacing: 8) {
            Text(activity.title).font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            Text(activity.since, style: .timer).font(.meta).monospacedDigit().foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 8)
            if activity.stoppable {
                Button("Stop") { catalog.stop(activity) }
                    .buttonStyle(.pill(.quiet, .small))
                    .fixedSize()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            HStack(spacing: 6) {
                ForEach(catalog.actions.filter { !$0.hidden }, id: \.id) { action in
                    Button(action.name) { catalog.run(action) }
                        .buttonStyle(.pill(.accent, .small))
                        .fixedSize()
                        .help(action.hotkeyLabel ?? action.name)
                }
            }
            Spacer(minLength: 8)
            IconButton(icon: .chartNoAxesColumn, help: "Insights") { model.page = .insights }
            IconButton(icon: .puzzle, help: extensionsHelp) { model.page = .extensions }
                .overlay(alignment: .topTrailing) {
                    if extensions.updateCount > 0 {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6).offset(x: -6, y: 6)
                    }
                }
            IconButton(icon: .settings, help: "Settings") { model.page = .settings }
                .keyboardShortcut(",", modifiers: .command)
            IconButton(icon: .power, help: "Quit Voz", action: model.actions.quit)
        }
        .padding(.trailing, -8)
    }

    @ViewBuilder
    private var status: some View {
        switch model.status {
        case .ready:
            EmptyView()
        case .recording:
            HStack(spacing: 6) {
                RecordingMark()
                Text("Recording").font(.ui(12, weight: .medium)).foregroundStyle(Theme.recording)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Theme.recording.opacity(0.12), in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        default:
            Text(model.status.title).font(.meta).foregroundStyle(Theme.inkSecondary)
        }
    }

    private var resultCount: String {
        switch records.count {
        case 0: "No results"
        case 1: "1 result"
        case let count: "\(count) results"
        }
    }

    private var extensionsHelp: String {
        switch extensions.updateCount {
        case 0: "Extensions"
        case 1: "Extensions, 1 update"
        case let count: "Extensions, \(count) updates"
        }
    }

    private func moveSelection(by step: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !records.isEmpty else { return .ignored }
        let current = records.firstIndex { $0.id == selectedID }
        let next = current.map { min(max($0 + step, 0), records.count - 1) } ?? (step > 0 ? 0 : records.count - 1)
        selectedID = records[next].id
        proxy.scrollTo(records[next].id)
        return .handled
    }

    private func copySelection() {
        guard let record = records.first(where: { $0.id == selectedID }) ?? records.first else { return }
        model.copy(record)
    }
}

private struct DayHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.display(11))
            .foregroundStyle(Theme.inkTertiary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

private struct TranscriptRow: View {
    let record: TranscriptRecord
    let query: String
    let time: String
    let height: CGFloat
    let selected: Bool
    let copied: Bool
    let copy: () -> Void
    let delete: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 10) {
                if record.source == nil {
                    AppIcon(bundleID: record.appBundleID, size: 24)
                } else {
                    Icon(.puzzle, size: 16).foregroundStyle(Theme.inkSecondary).frame(width: 24, height: 24)
                }
                Text(text)
                    .font(.ui(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(height: height)
            .background(selected ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(0.99))
        .help(record.source.map { "From \($0)" } ?? record.finalText)
        .contextMenu {
            Button("Copy", action: copy)
            if let file = record.file {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)]) }
            }
            Button("Delete", role: .destructive, action: delete)
        }
        .onHover(perform: hover)
        .animation(Theme.Motion.hover, value: copied)
    }

    private var text: AttributedString {
        let snippet = TranscriptSnippet.text(record.finalText, around: query)
        var attributed = AttributedString(snippet)
        if snippet.hasPrefix("… "), let ellipsisEnd = attributed.index(attributed.startIndex, offsetByCharacters: 2) as AttributedString.Index? {
            attributed[attributed.startIndex..<ellipsisEnd].foregroundColor = Theme.inkTertiary
        }
        for range in TranscriptSnippet.ranges(of: query, in: snippet) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].foregroundColor = Theme.accent
            attributed[lower..<upper].font = .ui(13, weight: .semibold)
        }
        return attributed
    }

    @ViewBuilder
    private var trailing: some View {
        if copied {
            Text("Copied")
                .font(.display(11))
                .foregroundStyle(Theme.accent)
                .transition(.blurReplace)
        } else {
            Text(time)
                .font(.display(11))
                .foregroundStyle(Theme.inkTertiary)
                .transition(.blurReplace)
        }
    }
}

private struct RecordingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Theme.recording)
            .frame(width: 6, height: 6)
            .opacity(dimmed ? 0.35 : 1)
            .animation(.easeInOut(duration: 1.1).repeatForever(), value: dimmed)
            .onAppear { dimmed = !reduceMotion }
    }
}

private struct IndeterminateBar: View {
    private static let segment: CGFloat = 0.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * Self.segment
            Capsule()
                .fill(Theme.accent)
                .frame(width: width)
                .offset(x: sweeping ? proxy.size.width - width : 0)
                .opacity(reduceMotion ? 0.5 : 1)
        }
        .frame(height: 4)
        .background(Theme.hairline, in: Capsule())
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.9).repeatForever(), value: sweeping)
        .onAppear { sweeping = !reduceMotion }
        .accessibilityLabel("Preparing")
    }
}
