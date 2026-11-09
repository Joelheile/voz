import Foundation
import LucideSwift

struct AppSearchExtension: Equatable {
    let name: String
    let summary: String?
}

struct AppSearchItem: Identifiable {
    enum Section: String {
        case app = "App"
        case extensions = "Extensions"
        case dictionary = "Dictionary"
        case transcripts = "Transcripts"
    }

    enum Target: Equatable {
        case page(PopoverPage)
        case extensionNamed(String)
        case transcript(TranscriptRecord.ID)
    }

    let section: Section
    let title: String
    var detail: String? = nil
    var keywords: [String] = []
    let icon: LucideIconName
    let target: Target

    var id: String { "\(section.rawValue)/\(title)/\(target)" }

    func matches(_ terms: [Substring]) -> Bool {
        let haystack = ([title, detail ?? ""] + keywords).joined(separator: " ")
        return terms.allSatisfy { haystack.localizedStandardContains($0) }
    }
}

/// What Cmd+K finds. Places in the app come first because few match, so they don't get buried under transcripts.
@MainActor
enum AppSearch {
    private static let transcriptLimit = 20

    private static let pages = [
        AppSearchItem(section: .app, title: "Insights", keywords: ["stats", "usage", "words"], icon: .chartNoAxesColumn, target: .page(.insights)),
        AppSearchItem(section: .app, title: "Dictionary", keywords: ["vocabulary", "words"], icon: .bookA, target: .page(.dictionary)),
        AppSearchItem(section: .app, title: "Extensions", keywords: ["plugins", "packages"], icon: .puzzle, target: .page(.extensions)),
        AppSearchItem(section: .app, title: "Settings", keywords: ["preferences"], icon: .settings, target: .page(.settings)),
        AppSearchItem(section: .app, title: "Speech model", keywords: ["parakeet", "whisper", "transcription"], icon: .cpu, target: .page(.speechModel)),
        AppSearchItem(section: .app, title: "Languages", keywords: ["language"], icon: .globe, target: .page(.languages)),
        AppSearchItem(section: .app, title: "Cleanup", keywords: ["filler", "punctuation"], icon: .wandSparkles, target: .page(.cleanup)),
        AppSearchItem(section: .app, title: "Cleanup prompt", icon: .wandSparkles, target: .page(.cleanupPrompt)),
        AppSearchItem(section: .app, title: "Cleanup steps", icon: .wandSparkles, target: .page(.cleanupSteps)),
        AppSearchItem(section: .app, title: "AI model", keywords: ["chatgpt", "claude", "apple"], icon: .bot, target: .page(.aiModel)),
        AppSearchItem(section: .app, title: "Privacy and debug log", keywords: ["telemetry", "logs"], icon: .shield, target: .page(.privacy)),
        AppSearchItem(section: .app, title: "What's new", keywords: ["changelog", "update", "release"], icon: .scrollText, target: .page(.whatsNew)),
        AppSearchItem(section: .app, title: "Feedback", keywords: ["bug", "report"], icon: .messageSquare, target: .page(.feedback)),
        AppSearchItem(section: .app, title: "Product tour", keywords: ["help"], icon: .play, target: .page(.tour)),
    ]

    private static let settings = [
        AppSearchItem(section: .app, title: "Shortcut", detail: "Settings", keywords: ["hotkey", "key"], icon: .keyboard, target: .page(.settings)),
        AppSearchItem(section: .app, title: "Mode", detail: "Settings", keywords: ["tap", "hold", "talk"], icon: .hand, target: .page(.settings)),
        AppSearchItem(section: .app, title: "Output", detail: "Settings", keywords: ["type", "paste", "copy", "clipboard"], icon: .type, target: .page(.settings)),
        AppSearchItem(section: .app, title: "Microphone", detail: "Settings", keywords: ["input", "audio"], icon: .mic, target: .page(.settings)),
        AppSearchItem(section: .app, title: "High quality headphones", detail: "Settings", keywords: ["bluetooth", "airpods", "call quality", "muffled"], icon: .headphones, target: .page(.settings)),
        AppSearchItem(section: .app, title: "Live preview", detail: "Settings", keywords: ["draft"], icon: .textCursorInput, target: .page(.settings)),
        AppSearchItem(section: .app, title: "Mute other apps", detail: "Settings", keywords: ["silence", "sound"], icon: .volumeX, target: .page(.settings)),
        AppSearchItem(section: .app, title: "Sound cues", detail: "Settings", keywords: ["audio"], icon: .volume2, target: .page(.settings)),
        AppSearchItem(section: .app, title: "Launch at login", detail: "Settings", keywords: ["startup", "open"], icon: .power, target: .page(.settings)),
    ]

    /// With nothing typed, the list offers the places you can go. `transcripts` already matched the query in the store.
    static func results(
        for query: String,
        words: [String],
        extensions: [AppSearchExtension],
        transcripts: [TranscriptRecord],
        now: Date
    ) -> [AppSearchItem] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return pages }
        let extensionItems = extensions.map {
            AppSearchItem(section: .extensions, title: ExtensionsModel.displayName($0.name), keywords: [$0.name, $0.summary ?? ""], icon: .puzzle, target: .extensionNamed($0.name))
        }
        let wordItems = words.map {
            AppSearchItem(section: .dictionary, title: $0, icon: .bookA, target: .page(.dictionary))
        }
        let places = (pages + settings + extensionItems + wordItems).filter { $0.matches(terms) }
        let transcriptItems = transcripts.prefix(transcriptLimit).map {
            AppSearchItem(
                section: .transcripts,
                title: TranscriptSnippet.text($0.finalText, around: query),
                detail: RecentTime.label(for: $0.createdAt, now: now),
                icon: .fileText,
                target: .transcript($0.id)
            )
        }
        return places + transcriptItems
    }
}
