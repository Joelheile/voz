import SwiftUI
import VozCore

struct CleanupPromptPage: View {
    @ObservedObject var settings: AppSettings
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Cleanup prompt", back: back)
            Text("Voz cleans up each dictation with this prompt, on your Mac. Your dictionary words go at the end.")
                .font(.meta)
                .lineSpacing(2)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $settings.cleanupPrompt)
                .font(.ui(12))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 320)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hairline))
            HStack {
                Spacer(minLength: 0)
                Button("Reset to default") { settings.cleanupPrompt = CleanupPrompt.standard }
                    .buttonStyle(.pill(.quiet, height: 28))
                    .disabled(settings.cleanupPrompt == CleanupPrompt.standard)
            }
        }
    }
}
