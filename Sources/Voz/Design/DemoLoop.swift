import SwiftUI

enum Keyframes {
    static func ramp(_ time: Double, from start: Double, to end: Double) -> Double {
        let progress = min(max((time - start) / (end - start), 0), 1)
        return 1 - pow(1 - progress, 3)
    }

    static func typed(_ text: String, progress: Double) -> String {
        let count = Int(Double(text.count) * min(max(progress, 0), 1))
        return String(text.prefix(count))
    }

    static func loopTime(_ elapsed: Double, duration: Double) -> Double {
        elapsed.truncatingRemainder(dividingBy: duration)
    }

    static func fade(_ time: Double, duration: Double) -> Double {
        min(ramp(time, from: 0, to: 0.35), 1 - ramp(time, from: duration - 0.45, to: duration))
    }
}

struct DemoLoop<Content: View>: View {
    let duration: Double
    let rest: Double
    @ViewBuilder let content: (Double) -> Content
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content(rest)
        } else {
            TimelineView(.animation) { context in
                let time = Keyframes.loopTime(context.date.timeIntervalSince(start), duration: duration)
                content(time).opacity(Keyframes.fade(time, duration: duration))
            }
        }
    }
}
