import Observation

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
    @ObservationIgnored var level: Float = 0
}
