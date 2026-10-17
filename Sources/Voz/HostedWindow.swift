import AppKit
import SwiftUI

@MainActor
final class HostedWindow {
    let window: NSWindow

    init(title: String, size: CGSize, minSize: CGSize? = nil, content: some View) {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = []
        window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if minSize != nil { window.styleMask.insert(.resizable) }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.canvasNSColor
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        if let minSize { window.contentMinSize = minSize }
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }
}
