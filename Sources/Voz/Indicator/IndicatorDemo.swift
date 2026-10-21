import Foundation

@MainActor
enum IndicatorDemo {
    static let launchArgument = "--demo-indicator"

    static func run(on indicator: IndicatorController) async {
        try? await Task.sleep(for: .milliseconds(500))
        let start = Date.now
        indicator.levelSource = {
            let seconds = Date.now.timeIntervalSince(start)
            let envelope = 0.5 + 0.5 * sin(seconds * 2.3)
            let syllables = abs(sin(seconds * 9.5))
            return Float(min(1, envelope * syllables * 1.1))
        }
        indicator.showRecording()
        try? await Task.sleep(for: .seconds(3.5))
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
