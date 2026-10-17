import AppKit
import VozCore

enum SoundCue: String {
    case start
    case stop
}

@MainActor
enum SoundCues {
    private static var current: NSSound?

    @discardableResult
    static func play(_ cue: SoundCue) -> Bool {
        guard UserDefaults.standard.bool(forKey: SettingsKey.soundCues) else { return false }
        guard
            let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Sounds"),
            let sound = NSSound(contentsOf: url, byReference: true)
        else {
            Log.app.error("Sound cue missing: \(cue.rawValue)")
            return false
        }
        current = sound
        return sound.play()
    }
}
