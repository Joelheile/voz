import Foundation

@MainActor
enum IndicatorDemo {
    static let launchArgument = "--demo-indicator"

    static func run(on indicator: IndicatorController) async {
        try? await Task.sleep(for: .milliseconds(500))
        indicator.showRecording()
        let frames = 210
        for frame in 0..<frames {
            let seconds = Double(frame) / 60
            let envelope = 0.5 + 0.5 * sin(seconds * 2.3)
            let syllables = abs(sin(seconds * 9.5))
            indicator.pushLevel(Float(min(1, envelope * syllables * 1.1)))
            try? await Task.sleep(for: .milliseconds(16))
        }
        indicator.showTranscribing()
        try? await Task.sleep(for: .seconds(2))
        indicator.showOutcome(.done)
        try? await Task.sleep(for: .seconds(1.8))
        indicator.showRecording()
        try? await Task.sleep(for: .seconds(1.2))
        indicator.showOutcome(.failed)
        try? await Task.sleep(for: .seconds(1.8))
    }
}
