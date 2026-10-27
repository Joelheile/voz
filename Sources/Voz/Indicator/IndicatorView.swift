import Observation
import SwiftUI

enum IndicatorMotion {
    static let open = Animation.spring(duration: 0.22, bounce: 0.15)
    static let close = Animation.spring(duration: 0.2, bounce: 0)
    static let reducedMotion = Animation.easeInOut(duration: 0.2)
    static let stateSwap = Animation.snappy(duration: 0.25)
    static let contentEnter = Animation.spring(duration: 0.22, bounce: 0.1)
    static let contentExit = Animation.easeOut(duration: 0.1)
    static let previewUpdate = Animation.smooth(duration: 0.14)
    static let leadingDelay = 0.06
    static let trailingDelay = 0.0
    static let enterBlur: CGFloat = 8
    static let exitBlur: CGFloat = 4
    static let hiddenScaleX: CGFloat = 0.4
    static let hiddenScaleY: CGFloat = 0.85
    static let pillExit = Animation.easeOut(duration: 0.15)
    static let pillHiddenScale: CGFloat = 0.9
    static let pillHiddenOffset: CGFloat = -6
}

struct NotchContentEffect: ViewModifier {
    let blur: CGFloat
    let scale: CGSize
    let opacity: Double
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(x: scale.width, y: scale.height, anchor: anchor)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static func notchContent(anchor: UnitPoint, delay: Double) -> AnyTransition {
        let visible = NotchContentEffect(blur: 0, scale: CGSize(width: 1, height: 1), opacity: 1, anchor: anchor)
        let hidden = { (blur: CGFloat) in
            NotchContentEffect(
                blur: blur,
                scale: CGSize(width: IndicatorMotion.hiddenScaleX, height: IndicatorMotion.hiddenScaleY),
                opacity: 0,
                anchor: anchor
            )
        }
        return .asymmetric(
            insertion: AnyTransition.modifier(active: hidden(IndicatorMotion.enterBlur), identity: visible)
                .animation(IndicatorMotion.contentEnter.delay(delay)),
            removal: AnyTransition.modifier(active: hidden(IndicatorMotion.exitBlur), identity: visible)
                .animation(IndicatorMotion.contentExit)
        )
    }

    static var pill: AnyTransition {
        let hidden = AnyTransition.scale(scale: IndicatorMotion.pillHiddenScale, anchor: .top)
            .combined(with: .offset(y: IndicatorMotion.pillHiddenOffset))
            .combined(with: .opacity)
        return .asymmetric(
            insertion: hidden.animation(IndicatorMotion.open),
            removal: hidden.animation(IndicatorMotion.pillExit)
        )
    }
}

struct IndicatorView: View {
    let model: IndicatorModel
    let layout: IndicatorLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation {
        if reduceMotion { return IndicatorMotion.reducedMotion }
        return model.isExpanded ? IndicatorMotion.open : IndicatorMotion.close
    }

    var body: some View {
        indicator
            .frame(width: layout.windowFrame.width, height: layout.windowFrame.height, alignment: .top)
            .keyframeAnimator(initialValue: 0.0, trigger: model.shakeCount) { view, offset in
                view.offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-5, duration: 0.07)
                    CubicKeyframe(5, duration: 0.1)
                    CubicKeyframe(-3, duration: 0.1)
                    CubicKeyframe(0, duration: 0.13)
                }
            }
    }

    @ViewBuilder private var indicator: some View {
        switch layout.style {
        case .notch: notch
        case .floating: pill
        }
    }

    private func transition(anchor: UnitPoint, delay: Double) -> AnyTransition {
        reduceMotion ? .opacity.animation(IndicatorMotion.reducedMotion) : .notchContent(anchor: anchor, delay: delay)
    }

    private var notchWidth: CGFloat {
        reduceMotion || model.isExpanded ? layout.panelFrame.width : layout.collapsedWidth
    }

    private var showsPreview: Bool { model.isExpanded && !model.preview.isEmpty }

    private var notchShape: NotchShape {
        NotchShape(
            topRadius: 6,
            bottomRadius: showsPreview ? 20 : model.isExpanded ? 14 : 10
        )
    }

    private var preview: some View {
        TranscriptPreview(text: model.preview)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.previewFrame = $0 }
    }

    private var notch: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    wing(alignment: .trailing, anchor: .trailing, delay: IndicatorMotion.leadingDelay) {
                        IndicatorLeading(model: model)
                    }
                    Spacer(minLength: layout.collapsedWidth)
                    wing(alignment: .leading, anchor: .leading, delay: IndicatorMotion.trailingDelay) {
                        IndicatorTrailing(model: model)
                    }
                }
                .frame(height: layout.panelFrame.height)
                if showsPreview {
                    preview
                        .padding(.horizontal, notchShape.topRadius + 14)
                        .padding(.top, 2)
                        .padding(.bottom, 14)
                        .transition(transition(anchor: .top, delay: 0))
                }
            }
            .frame(width: layout.panelFrame.width)
            .background {
                notchShape.fill(.black).frame(width: notchWidth)
            }
            .mask { notchShape.frame(width: notchWidth) }
            Rectangle()
                .fill(.black)
                .frame(width: max(notchWidth - 2 * notchShape.topRadius, 0), height: 1)
        }
        .opacity(reduceMotion && !model.isExpanded ? 0 : 1)
        .animation(animation, value: model.isExpanded)
        .animation(previewAnimation, value: model.preview)
    }

    private var previewAnimation: Animation {
        reduceMotion ? IndicatorMotion.reducedMotion : IndicatorMotion.previewUpdate
    }

    private var pill: some View {
        VStack(spacing: IndicatorLayout.pillGap) {
            pillBody
            if showsPreview {
                preview
                    .padding(14)
                    .frame(width: IndicatorLayout.previewWidth)
                    .background { floatingSurface(RoundedRectangle(cornerRadius: 16)) }
                    .transition(reduceMotion ? .opacity.animation(IndicatorMotion.reducedMotion) : .pill)
            }
        }
        .padding(.top, IndicatorLayout.shadowMargin)
        .animation(previewAnimation, value: model.preview)
    }

    private func floatingSurface(_ shape: some InsettableShape) -> some View {
        ZStack {
            shape.fill(.black).shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            Color.clear.hud(shape)
        }
    }

    private var pillBody: some View {
        ZStack {
            if model.isExpanded {
                floatingSurface(Capsule())
                .transition(reduceMotion ? .opacity.animation(IndicatorMotion.reducedMotion) : .pill)
            }
            HStack(spacing: 0) {
                revealed(anchor: .trailing, delay: IndicatorMotion.leadingDelay) {
                    IndicatorLeading(model: model)
                }
                Spacer(minLength: 0)
                revealed(anchor: .leading, delay: IndicatorMotion.trailingDelay) {
                    IndicatorTrailing(model: model)
                }
                .frame(width: LevelBarsGeometry.visibleWidth + LevelBarsGeometry.trailingInset)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
        }
        .frame(width: IndicatorLayout.pillSize.width, height: IndicatorLayout.pillSize.height)
        .animation(animation, value: model.isExpanded)
    }

    private func revealed<Content: View>(
        anchor: UnitPoint,
        delay: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            if model.isExpanded {
                content().transition(transition(anchor: anchor, delay: delay))
            }
        }
    }

    private func wing<Content: View>(
        alignment: Alignment,
        anchor: UnitPoint,
        delay: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        revealed(anchor: anchor, delay: delay, content: content)
        .frame(width: IndicatorLayout.sideWidth - notchShape.topRadius)
        .frame(width: IndicatorLayout.sideWidth, alignment: alignment)
    }
}

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
    var preview = ""
    @ObservationIgnored var previewFrame = CGRect.zero
    @ObservationIgnored var levels = LevelHistory()
}

struct IndicatorLeading: View {
    let model: IndicatorModel

    var body: some View {
        Text(
            timerInterval: model.recordingStart...model.recordingStart.addingTimeInterval(3600),
            pauseTime: model.recordingEnd,
            countsDown: false,
            showsHours: false
        )
        .font(.ui(12, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.primary.opacity(model.state == .recording ? 0.9 : 0.4))
        .animation(.easeOut(duration: 0.2), value: model.state)
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
                ResultSymbol(name: "checkmark", color: .primary, effect: .drawOn).transition(swap)
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
