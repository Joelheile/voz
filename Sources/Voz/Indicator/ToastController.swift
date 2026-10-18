import AppKit
import SwiftUI

@MainActor
@Observable
final class ToastModel {
    var text = ""
    var isShown = false
}

@MainActor
final class ToastController {
    private static let maxWidth: CGFloat = 340
    private static let gapBelowMenuBar: CGFloat = 46
    private static let fadeDuration = Duration.milliseconds(250)

    private let model = ToastModel()
    private let panel = IndicatorPanel()
    private var lifecycle: Task<Void, Never>?

    func show(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let screen = ScreenResolver.targetScreen() else { return }
        lifecycle?.cancel()
        model.text = trimmed
        let hosting = NSHostingView(rootView: ToastView(model: model, maxWidth: Self.maxWidth))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setFrame(NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - Self.gapBelowMenuBar - size.height,
            width: size.width,
            height: size.height
        ), display: true)
        panel.orderFrontRegardless()
        model.isShown = true
        let hold = Self.holdDuration(for: trimmed)
        lifecycle = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled, let self else { return }
            self.model.isShown = false
            try? await Task.sleep(for: Self.fadeDuration)
            guard !Task.isCancelled else { return }
            self.panel.orderOut(nil)
            self.panel.contentView = nil
        }
    }

    private static func holdDuration(for text: String) -> Duration {
        .milliseconds(min(2000 + text.count * 40, 6000))
    }
}

private struct ToastView: View {
    let model: ToastModel
    let maxWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(model.text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: maxWidth)
            .background {
                ZStack {
                    VisualEffectBackground()
                    Color.black.opacity(0.35)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .scaleEffect(reduceMotion || model.isShown ? 1 : 0.9, anchor: .top)
            .opacity(model.isShown ? 1 : 0)
            .animation(reduceMotion ? IndicatorMotion.reducedMotion : IndicatorMotion.open, value: model.isShown)
            .fixedSize()
    }
}
