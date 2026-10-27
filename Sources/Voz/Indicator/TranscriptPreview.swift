import SwiftUI

struct TranscriptPreview: View {
    let text: String

    var body: some View {
        Text(String(text.suffix(600)))
            .font(.ui(13))
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.leading)
            .lineLimit(4)
            .truncationMode(.head)
            .frame(width: 332, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .background(.black, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .accessibilityLabel("Dictation preview")
            .accessibilityValue(text)
    }
}
