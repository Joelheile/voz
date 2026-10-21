import Foundation
import VozCore

func makeRecord(_ text: String, at seconds: Double = 0) -> TranscriptRecord {
    TranscriptRecord(
        createdAt: Date(timeIntervalSince1970: seconds),
        rawText: text,
        audioSeconds: 2,
        sttMs: 100,
        totalMs: 200,
        model: "parakeet-tdt-v3",
        appBundleID: "com.apple.Notes",
        appName: "Notes"
    )
}

func makeTemporaryStorePath() -> String {
    NSTemporaryDirectory() + "voz-test-\(UUID().uuidString).sqlite"
}

func removeFile(atPath path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

func roundTripThroughJSON(_ hotkey: Hotkey) throws -> Hotkey {
    try JSONDecoder().decode(Hotkey.self, from: JSONEncoder().encode(hotkey))
}

func decodeHotkey(_ json: String) throws -> Hotkey {
    try JSONDecoder().decode(Hotkey.self, from: Data(json.utf8))
}
