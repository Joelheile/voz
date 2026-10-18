import Combine
import Foundation
import VozCore

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

    func state(for model: SpeechModel) -> ModelState {
        if model == .appleSpeech { return .ready(bytes: 0) }
        return states[model] ?? .notLoaded
    }

    func update(_ model: SpeechModel, _ state: ModelState) {
        states[model] = state
    }
}
