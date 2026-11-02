import AppKit
import SwiftUI

struct StarButton: View {
    private static let repo = URL(string: "https://github.com/Joelheile/voz")!

    let title: String
    var kind = PillKind.quiet
    var starred: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(Self.repo)
            starred()
        } label: {
            HStack(spacing: 5) {
                Icon(.star, size: 13)
                    .foregroundStyle(iconColor)
                Text(title)
            }
        }
        .buttonStyle(.pill(kind, .small))
        .fixedSize()
        .help("Star Voz on GitHub")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }

    private var iconColor: Color {
        guard kind == .quiet else { return kind.text }
        return hovering ? Theme.accent : Theme.inkSecondary
    }
}
