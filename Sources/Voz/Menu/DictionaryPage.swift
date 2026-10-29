import SwiftUI

struct DictionaryPage: View {
    @ObservedObject var model: VocabularyModel
    let back: () -> Void
    @FocusState private var draftFocused: Bool

    private var query: String { model.draft.trimmingCharacters(in: .whitespaces) }

    private var words: [VocabularyWord] {
        model.snapshot.words
            .filter { query.isEmpty || $0.word.localizedCaseInsensitiveContains(query) }
            .sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    private var suggestions: [VocabularySuggestion] {
        model.snapshot.suggestions.filter { query.isEmpty || $0.word.localizedCaseInsensitiveContains(query) }
    }

    private var canAdd: Bool {
        !query.isEmpty && !model.snapshot.words.contains { $0.word.caseInsensitiveCompare(query) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Dictionary", back: back)
            PageNote(text: "Names and terms Voz spells the way you enter them.")
            field
            CappedScrollView(maxHeight: 380) {
                VStack(alignment: .leading, spacing: 16) {
                    if !suggestions.isEmpty { suggestionBadges }
                    wordChips
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(Theme.Motion.section, value: model.snapshot)
        .onAppear { draftFocused = true }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Icon(.search).foregroundStyle(Theme.inkTertiary)
            TextField("Find or add a word", text: $model.draft)
                .textFieldStyle(.plain)
                .font(.ui(13))
                .foregroundStyle(Theme.ink)
                .focused($draftFocused)
                .onSubmit { if canAdd { model.addDraft() } }
            if canAdd {
                Button("Add", action: model.addDraft)
                    .buttonStyle(.pill(.accent, .small))
                    .help("Add \(query) (Return)")
                    .padding(.trailing, -8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .fieldBackground()
        .animation(Theme.Motion.hover, value: canAdd)
    }

    private var suggestionBadges: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Suggested from your edits")
            FlowLayout(spacing: 6) {
                ForEach(suggestions) { suggestion in
                    SuggestionBadge(word: suggestion.word, add: { model.accept(suggestion) }, dismiss: { model.dismiss(suggestion) })
                }
            }
        }
    }

    @ViewBuilder
    private var wordChips: some View {
        if model.snapshot.words.isEmpty {
            Text("No words yet")
                .font(.ui(13))
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity, minHeight: 56)
        } else if !words.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(words) { word in
                    WordChip(word: word.word) { model.remove(word) }
                }
            }
        }
    }
}

private struct SuggestionBadge: View {
    let word: String
    let add: () -> Void
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) {
                HStack(spacing: 5) {
                    Icon(.plus, size: 12)
                    Text(word).font(.ui(13, weight: .medium))
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(0.96))
            .help("Add \(word)")
            Button(action: dismiss) {
                Icon(.x, size: 11)
                    .padding(.leading, 2)
                    .padding(.trailing, 10)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .opacity(hovering ? 1 : 0.5)
        }
        .foregroundStyle(Theme.accent)
        .background(Theme.accent.opacity(hovering ? 0.14 : 0.09), in: Capsule())
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

private struct WordChip: View {
    let word: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(word).font(.ui(13)).foregroundStyle(Theme.ink)
            Button(action: remove) {
                Icon(.x, size: 11)
                    .foregroundStyle(hovering ? Theme.ink : Theme.inkTertiary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 28)
        .background(Theme.selected.opacity(hovering ? 1 : 0.6), in: Capsule())
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}
