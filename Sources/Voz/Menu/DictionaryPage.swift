import SwiftUI

struct DictionaryPage: View {
    @ObservedObject var model: VocabularyModel
    let back: () -> Void
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Dictionary", back: back)
            Text("Names and terms Voz spells the way you enter them.")
                .font(.meta)
                .foregroundStyle(Theme.inkSecondary)
            addRow
            CappedScrollView(maxHeight: 380) {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.snapshot.suggestions.isEmpty { suggestions }
                    words
                }
            }
        }
        .onAppear { draftFocused = true }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("Add a word or name", text: $model.draft)
                .textFieldStyle(.plain)
                .font(.ui(13))
                .foregroundStyle(Theme.ink)
                .focused($draftFocused)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Theme.canvas, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .onSubmit(model.addDraft)
            Button("Add", action: model.addDraft)
                .buttonStyle(.pill(.ink, height: 32))
                .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var suggestions: some View {
        PanelGroup(title: "Suggested from your edits") {
            ForEach(model.snapshot.suggestions) { suggestion in
                PanelRow(title: suggestion.word) {
                    HStack(spacing: 2) {
                        Button("Add") { model.accept(suggestion) }
                            .buttonStyle(.pill(.quiet, height: 26))
                        IconButton(symbol: "xmark", help: "Dismiss") { model.dismiss(suggestion) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var words: some View {
        if model.snapshot.words.isEmpty {
            Text("No words yet")
                .font(.ui(13))
                .foregroundStyle(Theme.inkTertiary)
                .frame(maxWidth: .infinity, minHeight: 56)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(model.snapshot.words) { word in
                    WordChip(word: word.word) { model.remove(word) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Theme.ink : Theme.inkTertiary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 28)
        .background(Theme.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}
