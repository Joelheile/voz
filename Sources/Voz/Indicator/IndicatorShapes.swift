import AppKit
import LucideSwift
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
    let icon: LucideIconName
    let color: Color
    let effect: Effect
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size: CGFloat = 15

    enum Effect {
        case reveal
        case bounce
    }

    var body: some View {
        Icon(icon, size: Self.size, strokeWidth: 2.25)
            .foregroundStyle(color)
            .mask(alignment: .leading) {
                Rectangle().frame(width: effect == .reveal && !arrived ? 0 : Self.size)
            }
            .scaleEffect(effect == .bounce && !arrived ? 0.8 : 1)
            .onAppear { withAnimation(reduceMotion ? nil : arrival) { arrived = true } }
    }

    private var arrival: Animation {
        effect == .reveal ? .easeOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0.3)
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
    func hud(_ shape: some InsettableShape) -> some View {
        background { VisualEffectBackground() }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
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

struct FileProgress: View {
    let model: IndicatorModel
    let style: IndicatorLayout.Style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: model.onCancel) {
            ZStack {
                if let progress = model.progress {
                    switch style {
                    case .notch: ProgressRing(progress: progress, showsCancel: model.isHovering)
                    case .floating: ProgressBar(progress: progress, showsCancel: model.isHovering)
                    }
                } else {
                    ProgressDots().opacity(model.isHovering ? 0 : 1)
                    CancelMark().opacity(model.isHovering ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style == .notch ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(0.92))
        .accessibilityLabel("Cancel transcription")
        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: model.progress)
        .animation(.easeOut(duration: 0.15), value: model.isHovering)
    }
}

struct CancelMark: View {
    var body: some View {
        Icon(.x, size: 11, strokeWidth: 2.25).foregroundStyle(.primary)
    }
}

struct ProgressRing: View {
    private static let size: CGFloat = 16
    private static let lineWidth: CGFloat = 2

    let progress: Double
    let showsCancel: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.2), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.primary.opacity(0.9), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Icon(.x, size: 8, strokeWidth: 2.25)
                .foregroundStyle(.primary)
                .opacity(showsCancel ? 1 : 0)
        }
        .frame(width: Self.size, height: Self.size)
    }
}

struct ProgressBar: View {
    private static let height: CGFloat = 4

    let progress: Double
    let showsCancel: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(.primary.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.9))
                        .frame(width: max(Self.height, LevelBarsGeometry.visibleWidth * progress))
                }
                .frame(width: LevelBarsGeometry.visibleWidth, height: Self.height)
                .opacity(showsCancel ? 0 : 1)
            CancelMark().opacity(showsCancel ? 1 : 0)
        }
        .padding(.trailing, LevelBarsGeometry.trailingInset)
    }
}
