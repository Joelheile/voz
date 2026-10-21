import Foundation
import Observation
import VozCore

enum IndicatorState: Equatable {
    case recording
    case transcribing
    case done
    case discarded
    case failed
}

@MainActor
@Observable
final class IndicatorModel {
    var state = IndicatorState.recording
    var isExpanded = false
    var shakeCount = 0
    var recordingStart = Date.now
    var recordingEnd: Date?
    @ObservationIgnored var levels = LevelHistory()
}
