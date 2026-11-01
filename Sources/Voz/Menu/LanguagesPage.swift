import SwiftUI

struct LanguagesPage: View {
    @ObservedObject var settings: AppSettings
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Languages", back: back)
            CappedScrollView(maxHeight: 560) {
                LanguagePicker(selection: $settings.languages)
            }
        }
    }
}

struct LanguagePicker: View {
    @Binding var selection: [SpeechLanguage]
    @State private var showsAll: Bool

    init(selection: Binding<[SpeechLanguage]>) {
        _selection = selection
        _showsAll = State(initialValue: selection.wrappedValue.contains { SpeechLanguage.others.contains($0) })
    }

    private var mixesAlphabets: Bool {
        SpeechLanguage.scriptFilter(for: selection) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelGroup(title: "Most spoken") {
                ForEach(SpeechLanguage.mostSpoken, id: \.self, content: row)
            }
            PanelGroup(title: "More languages") {
                if showsAll {
                    ForEach(SpeechLanguage.others, id: \.self, content: row)
                } else {
                    ActionRow(title: "Show all", value: "\(SpeechLanguage.others.count) more", action: { showsAll = true }) { hovering in
                        Icon(.chevronDown, size: 13)
                            .foregroundStyle(hovering ? Theme.ink : Theme.inkTertiary)
                    }
                }
            }
            if mixesAlphabets {
                Text("These languages use different alphabets, so Voz can't block letters from the wrong one.")
                    .font(.meta)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.section, value: showsAll)
        .animation(Theme.Motion.section, value: mixesAlphabets)
    }

    private func row(_ language: SpeechLanguage) -> some View {
        LanguageRow(language: language, selected: selection.contains(language)) {
            selection = SpeechLanguage.toggling(language, in: selection)
        }
    }
}

private struct LanguageRow: View {
    let language: SpeechLanguage
    let selected: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Text(language.name)
                    .font(.ui(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                if language.nativeName != language.name {
                    Text(language.nativeName)
                        .font(.meta)
                        .foregroundStyle(Theme.inkTertiary)
                }
                Spacer(minLength: 0)
                ZStack {
                    if selected {
                        Icon(.circleCheck, size: 15)
                            .foregroundStyle(Theme.accent)
                            .popIn()
                    } else {
                        Icon(.circle, size: 15)
                            .foregroundStyle(hovering ? Theme.inkSecondary : Theme.hairline)
                    }
                }
            }
            .frame(minHeight: Theme.Size.row)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}
