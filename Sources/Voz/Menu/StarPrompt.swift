import AppKit
import SwiftUI

enum StarPrompt {
    static let words = 2_000
    static let repo = URL(string: "https://github.com/Joelheile/voz")!

    static func shows(words: Int, dismissed: Bool) -> Bool {
        !dismissed && words >= Self.words
    }
}

struct StarPromptCard: View {
    let words: Int
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You've dictated \(words.formatted()) words with Voz. A star on GitHub helps other developers find it.")
                .font(.ui(13))
                .lineSpacing(2)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Star on GitHub") {
                    NSWorkspace.shared.open(StarPrompt.repo)
                    dismiss()
                }
                .buttonStyle(.pill(.accent, .small))
                Button("Not now", action: dismiss)
                    .buttonStyle(.pill(.quiet, .small))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.selected.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }
}
