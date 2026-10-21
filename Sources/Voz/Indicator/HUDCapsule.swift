import AppKit
import SwiftUI

extension View {
    func hudCapsule() -> some View {
        background { VisualEffectBackground() }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
