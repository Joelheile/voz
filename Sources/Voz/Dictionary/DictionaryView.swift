import SwiftUI
import VozCore

struct DictionaryView: View {
    @ObservedObject var model: VocabularyModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            PageHeader(title: "Dictionary", subtitle: "Names and terms voz should always spell your way.")
            AddWordRow(model: model)
            if !model.snapshot.suggestions.isEmpty {
                suggestions
            }
            words
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Suggested from your edits")
            VStack(spacing: 0) {
                ForEach(Array(model.snapshot.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        Text(suggestion.word).font(.rowTitle).foregroundStyle(Theme.ink)
                        Spacer()
                        Button("Add") { model.accept(suggestion) }
                            .buttonStyle(.pill(.quiet, height: 30))
                        IconButton(symbol: "xmark", help: "Dismiss") { model.dismiss(suggestion) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Your words")
            if model.snapshot.words.isEmpty {
                EmptyNote(symbol: "text.book.closed", title: "No words yet", detail: "Add a name or term above.")
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
}

private struct AddWordRow: View {
    @ObservedObject var model: VocabularyModel

    var body: some View {
        HStack(spacing: 12) {
            TextField("Add a word or name", text: $model.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Theme.canvas, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .onSubmit(model.addDraft)
            Button("Add", action: model.addDraft)
                .buttonStyle(.pill(.ink, height: 40))
                .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

private struct WordChip: View {
    let word: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(word).font(.system(size: 14)).foregroundStyle(Theme.ink)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hovering ? Theme.accent : Theme.inkTertiary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 34)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}
