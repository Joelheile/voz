import LucideSwift
import SwiftUI

struct Icon: View {
    let name: LucideIconName
    let size: CGFloat
    let strokeWidth: CGFloat

    init(_ name: LucideIconName, size: CGFloat = 14, strokeWidth: CGFloat = 1.25) {
        self.name = name
        self.size = size
        self.strokeWidth = strokeWidth
    }

    var body: some View {
        LucideIcon(name, size: size, strokeWidth: strokeWidth, absoluteStrokeWidth: true)
    }
}
