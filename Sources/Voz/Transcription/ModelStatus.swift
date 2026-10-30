import Combine
import SwiftUI

enum ModelState: Equatable, Sendable {
    case notLoaded
    case downloading(fraction: Double)
    case compiling
    case ready(bytes: Int64)
    case failed(String)
}

@MainActor
final class ModelStatus: ObservableObject {
    @Published private var states: [SpeechModel: ModelState] = [:]
    private var downloadStarts: [SpeechModel: Date] = [:]

    func state(for model: SpeechModel) -> ModelState {
        if model == .appleSpeech { return .ready(bytes: 0) }
        return states[model] ?? .notLoaded
    }

    func downloadElapsed(for model: SpeechModel) -> TimeInterval {
        downloadStarts[model].map { Date().timeIntervalSince($0) } ?? 0
    }

    func update(_ model: SpeechModel, _ state: ModelState) {
        if case .downloading = state {
            downloadStarts[model] = downloadStarts[model] ?? Date()
        } else {
            downloadStarts[model] = nil
        }
        states[model] = state
    }
}

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
            Text("Failed: \(message)").foregroundStyle(Theme.failure)
        }
    }
}
