import LucideSwift
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
    let updater: Updater
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
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.hairline))
            .toggleStyle(.accentSwitch)
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
                HomePage(model: model, history: sources.history, settings: sources.settings, catalog: sources.catalog, extensions: sources.extensions, updater: sources.updater)
            case .settings:
                SettingsPage(model: model, settings: sources.settings, catalog: sources.catalog)
            case .dictionary:
                DictionaryPage(model: sources.vocabulary, back: model.goBack)
            case .insights:
                InsightsPage(model: sources.stats, settings: sources.settings, back: model.goBack)
            case .extensions:
                ExtensionsPage(model: sources.extensions, catalog: sources.catalog, settings: sources.settings, toast: model.actions.toast, back: model.goBack)
            case .feedback:
                FeedbackPage(settings: sources.settings, toast: model.actions.toast, back: model.goBack)
            case .cleanupPrompt:
                CleanupPromptPage(settings: sources.settings, back: model.goBack)
            case .cleanupSteps:
                CleanupStepsPage(settings: sources.settings, catalog: sources.catalog, back: model.goBack)
            case .speechModel:
                SpeechModelPage(settings: sources.settings, status: sources.modelStatus, catalog: sources.catalog, back: model.goBack)
            case .languages:
                LanguagesPage(settings: sources.settings, back: model.goBack)
            case .cleanup:
                CleanupPage(model: model, settings: sources.settings, catalog: sources.catalog)
            case .privacy:
                PrivacyPage(settings: sources.settings, back: model.goBack)
            case .whatsNew:
                WhatsNewPage(settings: sources.settings, updater: sources.updater, releases: Changelog.bundled, checkForUpdates: model.actions.checkForUpdates, back: model.goBack)
            case .tour:
                TourPage(settings: sources.settings, open: { model.page = $0 }, finish: { withAnimation(Theme.Motion.section) { model.page = .home } })
            }
        }
    }
}

private struct HomePage: View {
    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 52

    @ObservedObject var model: PopoverModel
    @ObservedObject var history: HistoryModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var catalog: ExtensionCatalog
    @ObservedObject var extensions: ExtensionsModel
    @ObservedObject var updater: Updater
    @FocusState private var searchFocused: Bool
    @State private var selectedID: UUID?
    @State private var usage: UsageStats?

    private var milestone: Milestone? { usage.flatMap { Milestone.unseen(in: $0, seen: settings.milestonesSeen) } }
    private var starPromptWords: Int? {
        guard !settings.starPromptDismissed, let usage,
              StarPrompt.isDue(in: usage, dismissals: settings.starPromptDismissals) else { return nil }
        return usage[.all].words
    }

    private var records: [TranscriptRecord] { history.records }
    private var isSearching: Bool { !history.query.isEmpty }
    private var showsSearch: Bool { isSearching || !records.isEmpty }

    private var needsAttention: Bool { model.status != .ready }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                if needsAttention {
                    StatusBanner(status: model.status, hint: model.hint) { statusAction }
                        .transition(.opacity)
                }
                header(proxy: proxy)
                transcripts
                ForEach(catalog.activities, id: \.id, content: activityRow)
                if let words = starPromptWords {
                    StarCard(
                        words: words,
                        starred: { withAnimation(Theme.Motion.section) { settings.starPromptDismissed = true } },
                        dismiss: { withAnimation(Theme.Motion.section) { settings.starPromptDismissals += 1 } }
                    )
                }
                footer
            }
        }
        .onAppear { searchFocused = showsSearch }
        .task {
            usage = await history.usage()
            countMilestoneShow()
        }
        .onChange(of: history.query) { selectedID = nil }
    }

    @ViewBuilder
    private var statusAction: some View {
        switch model.status {
        case .loadingModel:
            Button("Cancel") { settings.speechModel = SpeechModel.appleSpeech.rawValue }
                .buttonStyle(.pill(.quiet, .small))
                .fixedSize()
                .help("Stop the download and use Apple speech")
        case let .permissionNeeded(fix):
            Button(fix.buttonTitle) { model.actions.fixPermission(fix) }
                .buttonStyle(.pill(.ink, .small))
                .fixedSize()
        case .modelFailed:
            Button("Try again", action: model.actions.retryModel)
                .buttonStyle(.pill(.quiet, .small))
                .fixedSize()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func header(proxy: ScrollViewProxy) -> some View {
        if showsSearch {
            search(proxy: proxy)
        } else {
            Text("Voz").font(.wordmark(17)).foregroundStyle(Theme.ink).padding(.leading, 4)
        }
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
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Theme.selected, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
            icon: record.source.map { ExtensionsModel.historyIcon(for: $0, in: extensions.installed) } ?? .puzzle,
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
            if activity.openable {
                Button("Open") { catalog.open(activity) }
                    .buttonStyle(.pill(.quiet, .small))
                    .fixedSize()
            }
            if activity.stoppable {
                Button("Stop") { catalog.stop(activity) }
                    .buttonStyle(.pill(.quiet, .small))
                    .fixedSize()
            }
        }
    }

    private func countMilestoneShow() {
        guard milestone != nil else { return }
        settings.milestoneShows += 1
        if settings.milestoneShows > Milestone.maxShows { markMilestonesSeen() }
    }

    private func markMilestonesSeen() {
        guard let usage else { return }
        settings.milestonesSeen = Milestone.markingSeen(in: usage, seen: settings.milestonesSeen)
        settings.milestoneShows = 0
    }

    private var hasActions: Bool {
        updater.availableVersion != nil || milestone != nil || catalog.actions.contains { !$0.hidden }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if hasActions {
                ViewThatFits(in: .horizontal) {
                    footerActions(milestone: milestone)
                    footerActions(milestone: nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            RowDivider()
            HStack(spacing: 2) {
                NavButton(icon: .chartNoAxesColumn, help: "Insights") {
                    markMilestonesSeen()
                    model.page = .insights
                }
                NavButton(icon: .bookA, help: "Dictionary") { model.page = .dictionary }
                NavButton(icon: .puzzle, help: extensionsHelp, badge: extensions.updateCount > 0) { model.page = .extensions }
                NavButton(icon: .settings, help: "Settings") { model.page = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            .padding(.bottom, -4)
        }
    }

    private func footerActions(milestone: Milestone?) -> some View {
        HStack(spacing: 6) {
            if let version = updater.availableVersion {
                Button("Update to \(version)", action: model.actions.checkForUpdates)
                    .buttonStyle(.pill(.accent, .small))
                    .fixedSize()
            }
            ForEach(catalog.actions.filter { !$0.hidden }, id: \.id) { action in
                Button(action.name) { catalog.run(action) }
                    .buttonStyle(.pill(.quiet, .small))
                    .fixedSize()
                    .help(action.hotkeyLabel ?? action.name)
            }
            if let milestone {
                MilestoneBadge(milestone: milestone) {
                    markMilestonesSeen()
                    model.page = .insights
                }
            }
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
            .font(.ui(11, weight: .semibold))
            .foregroundStyle(Theme.inkTertiary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

private struct TranscriptRow: View {
    let record: TranscriptRecord
    let icon: LucideIconName
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
            HStack(alignment: .top, spacing: 10) {
                if record.source == nil {
                    AppIcon(bundleID: record.appBundleID, size: 22)
                } else {
                    IconTile(icon, Color(nsColor: .systemIndigo))
                }
                Text(text)
                    .font(.ui(13))
                    .lineSpacing(1)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing.padding(.top, 2)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .frame(height: height, alignment: .top)
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
                .font(.ui(11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .transition(.blurReplace)
        } else {
            Text(time)
                .font(.ui(11))
                .monospacedDigit()
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
            .frame(width: 8, height: 8)
            .background(Circle().fill(Theme.recording.opacity(0.25)).padding(-3))
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

private struct StarCard: View {
    let words: Int
    let starred: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(.star, size: 16)
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You've dictated \(words.formatted()) words with Voz")
                        .font(.ui(13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Enjoying it? Give it a star on GitHub so other developers can find it.")
                        .font(.meta)
                        .lineSpacing(2)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                StarButton(title: "Star on GitHub", kind: .accent, starred: starred)
            }
            Spacer(minLength: 0)
            IconButton(icon: .x, help: "Dismiss", action: dismiss)
                .padding(.top, -6)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
        .background(Theme.selected, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .transition(.opacity)
    }
}

private struct MilestoneBadge: View {
    let milestone: Milestone
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Icon(.partyPopper, size: 14)
                    .foregroundStyle(Theme.accent)
                Text(milestone.title)
                    .font(.ui(12, weight: .medium))
                    .foregroundStyle(hovering ? Theme.ink : Theme.inkSecondary)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("See your Insights")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

private struct NavButton: View {
    let icon: LucideIconName
    let help: String
    var badge = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 16)
                .foregroundStyle(hovering ? Theme.ink : Theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(hovering ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(alignment: .top) {
                    if badge {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6).offset(x: 10, y: 5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(0.95))
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

private struct StatusBanner<Action: View>: View {
    let status: PopoverStatus
    let hint: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            mark
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                progress
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(10)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .animation(Theme.Motion.section, value: status)
    }

    private var detail: String {
        switch status {
        case let .loadingModel(detail, _) where !detail.isEmpty: detail
        case let .modelFailed(message) where hint.isEmpty: message
        default: hint
        }
    }

    private var tint: Color {
        switch status {
        case .recording, .modelFailed: Theme.recording
        case .permissionNeeded: Color(nsColor: .systemYellow)
        case .loadingModel: Theme.accent
        default: Theme.inkTertiary
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch status {
        case .recording: RecordingMark()
        case .modelFailed: Icon(.triangleAlert, size: 16, strokeWidth: 1.5).foregroundStyle(Theme.recording)
        case .permissionNeeded: Icon(.shield, size: 16, strokeWidth: 1.5).foregroundStyle(Color(nsColor: .systemYellow))
        case .loadingModel: Icon(.download, size: 16, strokeWidth: 1.5).foregroundStyle(Theme.accent)
        default: ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch status {
        case let .loadingModel(_, progress?):
            ProgressView(value: progress).progressViewStyle(.linear).tint(Theme.accent).padding(.top, 4)
        case .loadingModel:
            IndeterminateBar().padding(.top, 4)
        default:
            EmptyView()
        }
    }
}
