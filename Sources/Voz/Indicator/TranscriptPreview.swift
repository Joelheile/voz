import SwiftUI

struct TranscriptPreview: View {
    static let maxLines = 3
    static let lineHeight: CGFloat = 18
    static let fadeHeight: CGFloat = 32

    let text: String
    @State private var textHeight: CGFloat = 0
    @State private var isAtTop = true

    private var maxHeight: CGFloat { CGFloat(Self.maxLines) * Self.lineHeight }
    private var fadesTop: Bool { textHeight > maxHeight && !isAtTop }

    var body: some View {
        ScrollView {
            styledText
                .font(.ui(13))
                .lineSpacing(Self.lineHeight - 15)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { textHeight = $0 }
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y <= 0 }) { isAtTop = $1 }
        .frame(height: min(textHeight, maxHeight))
        .mask {
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: fadesTop ? Self.fadeHeight : 0)
                Color.black
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Dictation preview")
        .accessibilityValue(text)
    }

    private var styledText: Text {
        let lastWordStart = text.lastIndex(where: \.isWhitespace).map(text.index(after:)) ?? text.startIndex
        return Text(text[..<lastWordStart]).foregroundStyle(.primary.opacity(0.7))
            + Text(text[lastWordStart...]).foregroundStyle(.primary)
    }
}
