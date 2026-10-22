import AppKit
import SwiftUI

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

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = min(bottomRadius, rect.width / 4, rect.height - top)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + top, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - top, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

extension View {
    func hudCapsule() -> some View {
        background { VisualEffectBackground() }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
