import SwiftUI

struct IndicatorLeading: View {
    let model: IndicatorModel

    var body: some View {
        RecordingDot(isPulsing: model.state == .recording, color: color)
    }

    private var color: Color {
        switch model.state {
        case .recording: Theme.accentOnBlack
        case .transcribing, .discarded: .white.opacity(0.35)
        case .done: .green
        case .failed: .orange
        }
    }
}

struct IndicatorTrailing: View {
    let model: IndicatorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.state {
            case .recording, .discarded:
                LevelBars(model: model).transition(swap)
            case .transcribing:
                ProgressDots().transition(swap)
            case .done:
                ResultSymbol(name: "checkmark", color: .white, effect: .drawOn).transition(swap)
            case .failed:
                ResultSymbol(name: "exclamationmark", color: .orange, effect: .bounce).transition(swap)
            }
        }
        .animation(reduceMotion ? IndicatorMotion.reducedMotion : IndicatorMotion.stateSwap, value: model.state)
    }

    private var swap: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }
}
