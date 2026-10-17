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
    @Published private var states: [LanguageMode: ModelState] = [:]

    func state(for mode: LanguageMode) -> ModelState {
        states[mode] ?? .notLoaded
    }

    func update(_ mode: LanguageMode, _ state: ModelState) {
        states[mode] = state
    }
}
