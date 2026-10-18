import SwiftUI
import VozCore

struct ModelStatusLabel: View {
    @ObservedObject var status: ModelStatus
    let model: SpeechModel

    var body: some View {
        switch status.state(for: model) {
        case .notLoaded:
            Text("Not loaded")
        case let .downloading(fraction):
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
        case .compiling:
            Text("Preparing")
        case let .ready(bytes):
            Text("Ready, \(bytes.formatted(.byteCount(style: .file)))")
        case let .failed(message):
            Text("Failed: \(message)").foregroundStyle(.red)
        }
    }
}
