import SwiftUI

struct FeedbackPage: View {
    private enum Delivery: Equatable {
        case editing
        case sending
        case failed(String)
    }

    @ObservedObject var settings: AppSettings
    let toast: (String) -> Void
    let back: () -> Void
    @State private var message = ""
    @State private var email = ""
    @State private var delivery = Delivery.editing
    @FocusState private var messageFocused: Bool

    private var feedback: Feedback { Feedback(message: message, email: email, speechModel: settings.speechModel) }
    private var canSend: Bool { !feedback.isEmpty && delivery != .sending }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Feedback", back: back)
            PageNote(text: "Got an idea, a bug or a wish? Type or dictate it. I read every message. Your transcripts stay on this Mac.")
            TextEditor(text: $message)
                .font(.ui(13))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .focused($messageFocused)
                .padding(8)
                .frame(height: 140)
                .background(Theme.selected, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            TextField("Email, if you want a reply", text: $email)
                .textFieldStyle(.plain)
                .font(.ui(13))
                .foregroundStyle(Theme.ink)
                .fieldBackground()
            HStack(spacing: 8) {
                status
                Spacer(minLength: 0)
                Button(delivery == .sending ? "Sending" : "Send", action: send)
                    .buttonStyle(.pill(.accent, .small))
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Send (⌘Return)")
            }
            .animation(Theme.Motion.hover, value: delivery)
        }
        .onAppear { messageFocused = true }
    }

    @ViewBuilder
    private var status: some View {
        if case .failed(let reason) = delivery {
            Text(reason).font(.meta).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true).transition(.opacity)
        }
    }

    private func send() {
        let feedback = feedback
        delivery = .sending
        Task {
            do {
                try await feedback.send()
                back()
                toast("Feedback sent. Thanks.")
            } catch {
                delivery = .failed(error.localizedDescription)
            }
        }
    }
}
