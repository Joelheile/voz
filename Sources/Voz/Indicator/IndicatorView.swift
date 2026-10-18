import SwiftUI
import VozCore

enum IndicatorMotion {
    static let open = Animation.spring(duration: 0.34, bounce: 0.15)
    static let close = Animation.spring(duration: 0.32, bounce: 0)
    static let reducedMotion = Animation.easeInOut(duration: 0.2)
    static let stateSwap = Animation.snappy(duration: 0.3)
    static let contentEnter = Animation.spring(duration: 0.34, bounce: 0.1)
    static let contentExit = Animation.easeOut(duration: 0.12)
    static let leadingDelay = 0.08
    static let trailingDelay = 0.12
    static let enterBlur: CGFloat = 8
    static let exitBlur: CGFloat = 4
    static let hiddenScaleX: CGFloat = 0.4
    static let hiddenScaleY: CGFloat = 0.85
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
        Group {
            switch layout.style {
            case .notch: notch
            case .pill: pill
            }
        }
        .frame(width: layout.panelFrame.width, height: layout.panelFrame.height, alignment: .top)
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

    private func transition(anchor: UnitPoint, delay: Double) -> AnyTransition {
        reduceMotion ? .opacity.animation(IndicatorMotion.reducedMotion) : .notchContent(anchor: anchor, delay: delay)
    }

    private var notchWidth: CGFloat {
        reduceMotion || model.isExpanded ? layout.panelFrame.width : layout.collapsedWidth
    }

    private var notchShape: NotchShape {
        NotchShape(
            topRadius: 6,
            bottomRadius: model.isExpanded ? 14 : 10
        )
    }

    private var notch: some View {
        ZStack(alignment: .top) {
            notchShape
                .fill(.black)
                .frame(width: notchWidth, height: layout.panelFrame.height)
            HStack(spacing: 0) {
                wing(alignment: .trailing, anchor: .trailing, delay: IndicatorMotion.leadingDelay) {
                    IndicatorLeading(model: model)
                }
                Spacer(minLength: layout.collapsedWidth)
                wing(alignment: .leading, anchor: .leading, delay: IndicatorMotion.trailingDelay) {
                    IndicatorTrailing(model: model)
                }
            }
            .frame(width: layout.panelFrame.width, height: layout.panelFrame.height)
            .mask { notchShape.frame(width: notchWidth, height: layout.panelFrame.height) }
            Rectangle()
                .fill(.black)
                .frame(width: max(notchWidth - 2 * notchShape.topRadius, 0), height: 1)
        }
        .opacity(reduceMotion && !model.isExpanded ? 0 : 1)
        .animation(animation, value: model.isExpanded)
    }

    private func wing<Content: View>(
        alignment: Alignment,
        anchor: UnitPoint,
        delay: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            if model.isExpanded {
                content().transition(transition(anchor: anchor, delay: delay))
            }
        }
        .frame(width: IndicatorLayout.sideWidth - notchShape.topRadius)
        .frame(width: IndicatorLayout.sideWidth, alignment: alignment)
    }

    private var pill: some View {
        ZStack {
            VisualEffectBackground()
            Color.black.opacity(0.35)
            HStack(spacing: 12) {
                ZStack {
                    if model.isExpanded {
                        IndicatorLeading(model: model).transition(transition(anchor: .trailing, delay: IndicatorMotion.leadingDelay))
                    }
                }
                ZStack {
                    if model.isExpanded {
                        IndicatorTrailing(model: model).transition(transition(anchor: .leading, delay: IndicatorMotion.trailingDelay))
                    }
                }
                .frame(width: LevelBarsGeometry.totalWidth)
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .scaleEffect(reduceMotion || model.isExpanded ? 1 : 0.8, anchor: .top)
        .opacity(model.isExpanded ? 1 : 0)
        .animation(animation, value: model.isExpanded)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
