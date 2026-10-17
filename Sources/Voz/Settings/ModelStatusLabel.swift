import SwiftUI
import VozCore

struct ModelStatusLabel: View {
    @ObservedObject var status: ModelStatus
    let mode: LanguageMode

    var body: some View {
        switch status.state(for: mode) {
        case .notLoaded:
            Text("Not loaded")
        case let .downloading(fraction):
            Text("Downloading \(fraction.formatted(.percent.precision(.fractionLength(0))))")
        case .compiling:
            Text("Compiling")
        case let .ready(bytes):
            Text("Ready, \(bytes.formatted(.byteCount(style: .file)))")
        case let .failed(message):
            Text("Failed: \(message)").foregroundStyle(.red)
        }
    }
}
