import SwiftUI
import VozCore

struct LevelBars: View {
    let model: IndicatorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLive: Bool { model.state == .recording }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 15 : nil, paused: !isLive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: LevelBarsGeometry.barSpacing) {
                ForEach(0...LevelBarsGeometry.barCount, id: \.self) { slot in
                    let taper = reduceMotion ? 1 : LevelBarsGeometry.taper(slot: slot, time: time)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: LevelBarsGeometry.barWidth, height: LevelBarsGeometry.height(level: level(slot: slot, time: time), taper: taper))
                        .opacity(taper)
                }
            }
            .offset(x: reduceMotion ? 0 : LevelBarsGeometry.scrollOffset(time: time))
            .frame(width: LevelBarsGeometry.visibleWidth, height: LevelBarsGeometry.maxHeight, alignment: .trailing)
        }
        .padding(.trailing, LevelBarsGeometry.trailingInset)
    }

    private func level(slot: Int, time: Double) -> Float {
        if reduceMotion { return model.levels.latest }
        return model.levels.average(in: LevelBarsGeometry.sampleWindow(slot: slot, time: time))
    }
}

struct ProgressDots: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.primary)
                    .frame(width: 4.5, height: 4.5)
                    .opacity(phase ? 0.95 : 0.25)
                    .scaleEffect(phase ? 1 : 0.7)
                    .animation(
                        .easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(index) * 0.16),
                        value: phase
                    )
            }
        }
        .frame(height: LevelBarsGeometry.maxHeight)
        .onAppear { phase = true }
    }
}

struct ResultSymbol: View {
    let name: String
    let color: Color
    let effect: Effect
    @State private var arrived = false

    enum Effect {
        case drawOn
        case bounce
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color)
            .symbolEffect(.drawOn, isActive: effect == .drawOn && !arrived)
            .symbolEffect(.bounce, options: .nonRepeating, value: effect == .bounce && arrived)
            .onAppear { arrived = true }
    }
}
