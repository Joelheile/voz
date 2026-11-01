import FluidAudio
import Foundation

/// The languages Parakeet Ultra transcribes, ordered by how many people speak them.
enum SpeechLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case portuguese = "pt"
    case russian = "ru"
    case german = "de"
    case italian = "it"
    case polish = "pl"
    case ukrainian = "uk"
    case dutch = "nl"
    case romanian = "ro"
    case greek = "el"
    case hungarian = "hu"
    case czech = "cs"
    case swedish = "sv"
    case bulgarian = "bg"
    case danish = "da"
    case finnish = "fi"
    case slovak = "sk"
    case croatian = "hr"
    case lithuanian = "lt"
    case slovenian = "sl"
    case latvian = "lv"
    case estonian = "et"
    case maltese = "mt"

    static let mostSpokenCount = 8
    static let mostSpoken = Array(allCases.prefix(mostSpokenCount))
    static let others = allCases.dropFirst(mostSpokenCount).sorted { $0.name < $1.name }

    var name: String {
        Locale(identifier: "en").localizedString(forLanguageCode: rawValue) ?? rawValue
    }

    var nativeName: String {
        let locale = Locale(identifier: rawValue)
        return locale.localizedString(forLanguageCode: rawValue)?.capitalized(with: locale) ?? rawValue
    }

    var filterLanguage: Language {
        Language(rawValue: rawValue) ?? .english
    }

    /// Parakeet can only filter by alphabet, so a filter applies when every language shares one.
    static func scriptFilter(for languages: [SpeechLanguage]) -> Language? {
        let filters = languages.map(\.filterLanguage)
        guard let first = filters.first, filters.allSatisfy({ $0.script == first.script }) else { return nil }
        return first
    }

    static func defaults(preferred: [String] = Locale.preferredLanguages) -> [SpeechLanguage] {
        var languages: [SpeechLanguage] = []
        for identifier in preferred {
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier,
                  let language = SpeechLanguage(rawValue: code), !languages.contains(language) else { continue }
            languages.append(language)
        }
        return languages.isEmpty ? [.english] : languages
    }

    /// Keeps at least one language, in speaker order.
    static func toggling(_ language: SpeechLanguage, in selection: [SpeechLanguage]) -> [SpeechLanguage] {
        guard selection.contains(language) else { return allCases.filter { selection.contains($0) || $0 == language } }
        return selection.count > 1 ? selection.filter { $0 != language } : selection
    }

    static func summary(of languages: [SpeechLanguage]) -> String {
        languages.count > 2 ? "\(languages.count) languages" : languages.map(\.name).joined(separator: ", ")
    }
}
