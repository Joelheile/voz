import LucideSwift
import SwiftUI

struct Icon: View {
    let name: LucideIconName
    let size: CGFloat

    init(_ name: LucideIconName, size: CGFloat = 14) {
        self.name = name
        self.size = size
    }

    var body: some View {
        LucideIcon(name, size: size, strokeWidth: 1.75, absoluteStrokeWidth: true)
    }
}
