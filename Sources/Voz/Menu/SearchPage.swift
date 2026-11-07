import SwiftUI

/// Cmd+K: one field that finds transcripts from every day, places in the app, extensions and dictionary words.
struct SearchPage: View {
    private static let rowHeight: CGFloat = 34
    private static let visibleRows = 9

    @ObservedObject var model: PopoverModel
    @ObservedObject var history: HistoryModel
    @ObservedObject var vocabulary: VocabularyModel
    @ObservedObject var extensions: ExtensionsModel
    @FocusState private var fieldFocused: Bool
    @State private var selectedID: AppSearchItem.ID?

    private var results: [AppSearchItem] {
        AppSearch.results(
            for: history.query,
            words: vocabulary.snapshot.words.map(\.word),
            extensions: searchableExtensions,
            transcripts: history.listedDay == nil ? history.records : [],
            now: Date()
        )
    }

    /// Installed extensions and the ones you can get, each once
    private var searchableExtensions: [AppSearchExtension] {
        let installed = extensions.installed.map { AppSearchExtension(name: $0.name, summary: $0.description) }
        let names = Set(installed.map(\.name))
        return installed + extensions.listings.filter { !names.contains($0.name) }.map { AppSearchExtension(name: $0.name, summary: $0.summary) }
    }

    var body: some View {
        let results = results
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                SearchField(text: $history.query, prompt: "Search everything", focused: $fieldFocused)
                    .onSubmit { activate(highlighted(in: results), in: results) }
                    .onKeyPress(.downArrow) { move(by: 1, in: results, proxy: proxy) }
                    .onKeyPress(.upArrow) { move(by: -1, in: results, proxy: proxy) }
                    .onKeyPress(.escape) { dismiss() }
                if results.isEmpty {
                    Text("No results")
                        .font(.ui(13))
                        .foregroundStyle(Theme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    CappedScrollView(maxHeight: CGFloat(Self.visibleRows) * Self.rowHeight) {
                        list(results)
                    }
                    .padding(.horizontal, -8)
                }
            }
        }
        .onAppear { fieldFocused = true }
        .onChange(of: history.query) { selectedID = nil }
    }

    private func list(_ results: [AppSearchItem]) -> some View {
        let highlighted = highlighted(in: results)
        let hasSections = Set(results.map(\.section)).count > 1
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                if hasSections, index == 0 || results[index - 1].section != item.section {
                    Text(item.section.rawValue)
                        .font(.ui(11, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, index == 0 ? 0 : 8)
                        .padding(.bottom, 4)
                }
                AppSearchRow(
                    item: item,
                    height: Self.rowHeight,
                    selected: item.id == highlighted,
                    copied: item.target == .transcript(model.copiedID ?? UUID()),
                    activate: { activate(item.id, in: results) },
                    hover: { selectedID = $0 ? item.id : nil }
                )
                .id(item.id)
            }
        }
    }

    /// The first result stays highlighted, so Return does something the moment you stop typing
    private func highlighted(in results: [AppSearchItem]) -> AppSearchItem.ID? {
        results.contains { $0.id == selectedID } ? selectedID : results.first?.id
    }

    private func move(by step: Int, in results: [AppSearchItem], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        let current = results.firstIndex { $0.id == highlighted(in: results) } ?? 0
        let next = results[min(max(current + step, 0), results.count - 1)]
        selectedID = next.id
        proxy.scrollTo(next.id)
        return .handled
    }

    private func dismiss() -> KeyPress.Result {
        if history.query.isEmpty {
            model.page = .home
        } else {
            history.query = ""
        }
        return .handled
    }

    private func activate(_ id: AppSearchItem.ID?, in results: [AppSearchItem]) {
        guard let item = results.first(where: { $0.id == id }) else { return }
        switch item.target {
        case let .page(page):
            model.page = page
        case let .extensionNamed(name):
            model.page = .extensions
            Task { await extensions.reveal(name) }
        case let .transcript(id):
            if let record = history.records.first(where: { $0.id == id }) { model.copy(record) }
        }
    }
}

private struct AppSearchRow: View {
    let item: AppSearchItem
    let height: CGFloat
    let selected: Bool
    let copied: Bool
    let activate: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 10) {
                Icon(item.icon, size: 14)
                    .foregroundStyle(Theme.inkSecondary)
                Text(item.title)
                    .font(.ui(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if copied {
                    Icon(.check, size: 14).foregroundStyle(Theme.accent)
                } else if let detail = item.detail {
                    Text(detail)
                        .font(.meta)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(selected ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(0.99))
        .onHover(perform: hover)
    }
}
