import AppKit
import SwiftUI

struct AppIcon: View {
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        if let image = bundleID.flatMap({ AppIconCache.image(for: $0) }) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

@MainActor
private enum AppIconCache {
    private static var images: [String: NSImage?] = [:]

    static func image(for bundleID: String) -> NSImage? {
        if let cached = images[bundleID] { return cached }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        images[bundleID] = image
        return image
    }
}
