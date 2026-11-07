import AppKit
import LucideSwift
import SwiftUI

/// A one-line glass capsule under the notch. It leaves your keyboard alone, so pressing Return while you type can't press its button, and it goes away by itself unless the pointer is on it.
@MainActor
final class NoticeController {
    private static let hold = Duration.seconds(12)
    private static let gapBelowMenuBar: CGFloat = 8
    private static let fadeOut = Duration.milliseconds(200)

    private let visibility = NoticeVisibility()
    private let panel = NotePanel(contentRect: .zero)
    private var waiting: CheckedContinuation<String?, Never>?
    private var timer: Task<Void, Never>?
    private var hiding: Task<Void, Never>?

    /// Returns the button you pressed, or `nil` if the notice went away without an answer
    func show(title: String, icon: LucideIconName, later: String, action: String) async -> String? {
        finish(nil)
        guard let screen = ScreenResolver.targetScreen() else { return nil }
        hiding?.cancel()
        visibility.isShown = false
        let hosting = FirstClickHostingView(rootView: NoticeView(
            title: title,
            icon: icon,
            later: later,
            action: action,
            visibility: visibility,
            onAnswer: { [weak self] in self?.finish($0) },
            onHover: { [weak self] hovering in hovering ? self?.timer?.cancel() : self?.startTimer() }
        ))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.onClose = { [weak self] in self?.finish(nil) }
        panel.setFrame(NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - Self.gapBelowMenuBar - size.height,
            width: size.width,
            height: size.height
        ), display: true)
        panel.orderFrontRegardless()
        visibility.isShown = true
        startTimer()
        return await withCheckedContinuation { waiting = $0 }
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.hold)
            guard !Task.isCancelled else { return }
            self?.finish(nil)
        }
    }

    private func finish(_ answer: String?) {
        timer?.cancel()
        guard let waiting else { return }
        self.waiting = nil
        waiting.resume(returning: answer)
        visibility.isShown = false
        hiding = Task { [panel] in
            try? await Task.sleep(for: Self.fadeOut)
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

@MainActor
@Observable
final class NoticeVisibility {
    var isShown = false
}

/// The panel never takes focus before you click, so the first click has to press the button
private final class FirstClickHostingView: NSHostingView<NoticeView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct NoticeView: View {
    private static let height: CGFloat = 38
    private static let buttonInset: CGFloat = 7

    let title: String
    let icon: LucideIconName
    let later: String
    let action: String
    let visibility: NoticeVisibility
    let onAnswer: (String) -> Void
    let onHover: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation {
        if reduceMotion { return IndicatorMotion.reducedMotion }
        return visibility.isShown ? IndicatorMotion.open : IndicatorMotion.close
    }

    var body: some View {
        HStack(spacing: 7) {
            Icon(icon, size: 15)
                .foregroundStyle(Theme.ink)
            Text(title)
                .font(.ui(13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.trailing, 5)
            HStack(spacing: 6) {
                Button(later) { onAnswer(later) }
                    .buttonStyle(.pill(.outline, .small))
                Button(action) { onAnswer(action) }
                    .buttonStyle(.pill(.accent, .small))
            }
        }
        .fixedSize()
        .padding(.leading, 12)
        .padding(.trailing, Self.buttonInset)
        .frame(height: Self.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onHover(perform: onHover)
        .scaleEffect(reduceMotion || visibility.isShown ? 1 : 0.96, anchor: .top)
        .opacity(visibility.isShown ? 1 : 0)
        .animation(motion, value: visibility.isShown)
    }
}

/// Shows the notice with a sample update, so the real panel can be checked without publishing one. Prints the answer and exits.
enum NoticeDemo {
    static let launchArgument = "--demo-update-notice"

    static func run() async {
        let notice = UpdateNotice(version: "0.3.0", isDownloaded: true)
        let answer = await NoticeController().show(title: notice.title, icon: .circleArrowUp, later: UpdateNotice.later, action: notice.action)
        print(answer ?? "no answer")
    }
}
