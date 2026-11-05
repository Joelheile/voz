import Foundation

/// A name that may leave this Mac. Only the factories below can make one, so a fact can't carry a transcript, a window title or an unlisted app.
struct TelemetryName: Codable, Hashable, Sendable {
    let value: String

    fileprivate init(_ value: String) {
        self.value = value
    }

    static func app(_ bundleID: String?) -> TelemetryName {
        TelemetryName(bundleID.flatMap { UsageKeys.apps[$0] } ?? UsageKeys.other)
    }

    static func site(_ hostname: String) -> TelemetryName {
        var labels = hostname.split(separator: ".")
        while labels.count >= 2 {
            if let key = UsageKeys.sites[labels.joined(separator: ".")] { return TelemetryName(key) }
            labels.removeFirst()
        }
        return TelemetryName(UsageKeys.other)
    }

    static func model(_ id: String) -> TelemetryName {
        TelemetryName(SpeechModel.analyticsLabel(for: id))
    }

    static func failure(_ error: AppError) -> TelemetryName {
        TelemetryName(error.rawValue)
    }

    /// Git and local extensions stay unnamed, because their names can be private
    static func package(named name: String, in installed: [InstalledExtension]) -> TelemetryName? {
        guard case let .npm(package, _) = installed.first(where: { $0.name == name })?.source else { return nil }
        return TelemetryName(package)
    }
}

extension AnalyticsEvent {
    /// The fixed code `failure_day` counts this event under, if it counts at all
    var countedFailure: TelemetryName? {
        if case let .dictationDiscarded(reason) = self { return TelemetryName("discarded_\(reason.rawValue)") }
        return failure.map { TelemetryName($0.code) }
    }

    var milestone: UsageMilestone? {
        switch self {
        case let .setupStepViewed(stage):
            switch stage {
            case .access: .setupAccess
            case .languages: .setupLanguages
            case .model: .setupModel
            case .tryIt: .setupTryIt
            }
        case .setupCompleted: .setupCompleted
        case let .permissionResult(permission, true):
            switch permission {
            case .microphone: .permissionMicrophone
            case .accessibility: .permissionAccessibility
            case .inputMonitoring: .permissionInputMonitoring
            case .systemAudio: .permissionSystemAudio
            }
        default: nil
        }
    }
}

/// The public list of app and site names. Anything else is `other`, so unknown apps and websites never leave this Mac.
enum UsageKeys {
    static let other = "other"

    static let apps: [String: String] = [
        "com.apple.Safari": "safari", "com.google.Chrome": "chrome", "company.thebrowser.Browser": "arc",
        "company.thebrowser.dia": "dia", "com.brave.Browser": "brave", "com.microsoft.edgemac": "edge",
        "org.mozilla.firefox": "firefox", "app.zen-browser.zen": "zen", "com.vivaldi.Vivaldi": "vivaldi",
        "com.tinyspeck.slackmacgap": "slack", "com.hnc.Discord": "discord", "net.whatsapp.WhatsApp": "whatsapp",
        "ru.keepcoder.Telegram": "telegram", "org.whispersystems.signal-desktop": "signal", "com.apple.MobileSMS": "messages",
        "com.microsoft.teams2": "teams", "us.zoom.xos": "zoom", "com.apple.mail": "mail", "com.microsoft.Outlook": "outlook",
        "com.superhuman.electron": "superhuman", "notion.id": "notion", "md.obsidian": "obsidian", "com.apple.Notes": "notes",
        "com.apple.iWork.Pages": "pages", "com.microsoft.Word": "word", "com.linear": "linear", "com.figma.Desktop": "figma",
        "com.todesktop.230313mzl4w4u92": "cursor", "com.microsoft.VSCode": "vscode", "dev.zed.Zed": "zed",
        "com.exafunction.windsurf": "windsurf", "com.apple.dt.Xcode": "xcode", "com.apple.Terminal": "terminal",
        "com.googlecode.iterm2": "iterm", "com.mitchellh.ghostty": "ghostty", "dev.warp.Warp-Stable": "warp",
        "com.anthropic.claudefordesktop": "claude", "com.openai.chat": "chatgpt", "com.openai.codex": "codex",
    ]

    /// General work and chat sites only. Banks, health, adult and similar sites stay off this list.
    static let sites: [String: String] = [
        "chatgpt.com": "chatgpt", "claude.ai": "claude", "gemini.google.com": "gemini", "perplexity.ai": "perplexity",
        "mail.google.com": "gmail", "outlook.office.com": "outlook", "outlook.live.com": "outlook",
        "docs.google.com": "google-docs", "notion.so": "notion", "linear.app": "linear", "github.com": "github",
        "gitlab.com": "gitlab", "figma.com": "figma", "app.slack.com": "slack", "discord.com": "discord",
        "web.whatsapp.com": "whatsapp", "teams.microsoft.com": "teams", "x.com": "x", "linkedin.com": "linkedin",
        "reddit.com": "reddit",
    ]
}

/// Each step counts once per install, so a funnel is a ratio of counts with nothing linking the steps
enum UsageMilestone: String, Codable, Sendable {
    case setupAccess = "setup_access"
    case setupLanguages = "setup_languages"
    case setupModel = "setup_model"
    case setupTryIt = "setup_try_it"
    case setupCompleted = "setup_completed"
    case permissionMicrophone = "permission_microphone"
    case permissionAccessibility = "permission_accessibility"
    case permissionInputMonitoring = "permission_input_monitoring"
    case permissionSystemAudio = "permission_system_audio"
    case firstDictation = "first_dictation"
    case dictations10 = "dictations_10"
    case dictations100 = "dictations_100"
    case activeDays2 = "active_days_2"
    case activeDays7 = "active_days_7"
    case activeDays30 = "active_days_30"
    case firstExtension = "first_extension"
}

struct SettingsSnapshot: Equatable, Sendable {
    let cleanup: Bool
    let livePreview: Bool
    let insertIntoApp: Bool
    let soundCues: Bool
    let launchAtLogin: Bool
    let autoUpdate: Bool
    let betaUpdates: Bool
    let shareUsage: Bool
    let crashReports: Bool
    let speechModel: TelemetryName
}

/// Everything Voz sends outside a dictation event. Each fact is one event, so nothing in PostHog can rebuild one Mac's day.
enum TelemetryFact: Equatable, Sendable {
    case versionPing(VersionPing, version: String, previous: String?)
    case milestone(UsageMilestone)
    case dailyActive(firstOfWeek: Bool, firstOfMonth: Bool, weeksSinceFirstUse: String, words: Int, dictations: Int)
    case appDay(TelemetryName, words: Int, dictations: Int)
    case latencyDay(model: TelemetryName, medianMs: Int, dictations: Int)
    case failureDay(TelemetryName, count: Int)
    case extensionDay(package: TelemetryName, runs: Int)
    case extensionWeek(package: TelemetryName)
    case settingsWeek(SettingsSnapshot)
    case siteDay(TelemetryName, words: Int, dictations: Int)

    var name: String {
        switch self {
        case .versionPing: "version_ping"
        case .milestone: "milestone"
        case .dailyActive: "daily_active"
        case .appDay: "app_day"
        case .latencyDay: "latency_day"
        case .failureDay: "failure_day"
        case .extensionDay: "extension_day"
        case .extensionWeek: "extension_week"
        case .settingsWeek: "settings_week"
        case .siteDay: "site_day"
        }
    }

    var when: String {
        switch self {
        case .versionPing: "On install and on each update"
        case .milestone: "Once per install, per step"
        case .dailyActive: "After each UTC day you dictate"
        case .appDay: "After each UTC day, one per app"
        case .latencyDay: "After each UTC day, one per speech model"
        case .failureDay: "After each UTC day, one per error code"
        case .extensionDay: "After each UTC day, one per public npm extension you ran"
        case .extensionWeek: "Once a week, one per enabled public npm extension"
        case .settingsWeek: "Once a week"
        case .siteDay: "After each UTC day, one per site"
        }
    }

    /// Only site totals use the install ID, and only people who share usage send them
    var isLinked: Bool {
        if case .siteDay = self { return true }
        return false
    }

    func properties(in environment: TelemetryEnvironment) -> [String: AnalyticsValue] {
        switch self {
        case let .versionPing(kind, version, previous):
            var properties: [String: AnalyticsValue] = [
                "kind": .text(kind.rawValue), "version": .text(version), "channel": .text(UpdateChannel(version: version).rawValue),
            ]
            if let previous { properties["previous"] = .text(previous) }
            return properties
        case let .milestone(step):
            return ["step": .text(step.rawValue)]
        case let .dailyActive(firstOfWeek, firstOfMonth, weeksSinceFirstUse, words, dictations):
            return [
                "first_of_week": .flag(firstOfWeek), "first_of_month": .flag(firstOfMonth), "weeks_since_first_use": .text(weeksSinceFirstUse),
                "words": .integer(words), "dictations": .integer(dictations), "version": .text(environment.version),
                "channel": .text(environment.channel), "os_major": .integer(environment.osMajor), "chip": .text(environment.chipFamily),
            ]
        case let .appDay(app, words, dictations):
            return ["app": .text(app.value), "words": .integer(words), "dictations": .integer(dictations)]
        case let .latencyDay(model, medianMs, dictations):
            return ["model": .text(model.value), "median_ms": .integer(medianMs), "dictations": .integer(dictations), "version": .text(environment.version)]
        case let .failureDay(code, count):
            return ["code": .text(code.value), "count": .integer(count), "version": .text(environment.version)]
        case let .extensionDay(package, runs):
            return ["package": .text(package.value), "runs": .integer(runs)]
        case let .extensionWeek(package):
            return ["package": .text(package.value)]
        case let .settingsWeek(settings):
            return [
                "cleanup": .flag(settings.cleanup), "live_preview": .flag(settings.livePreview), "insert_into_app": .flag(settings.insertIntoApp),
                "sound_cues": .flag(settings.soundCues), "launch_at_login": .flag(settings.launchAtLogin), "auto_update": .flag(settings.autoUpdate),
                "beta_updates": .flag(settings.betaUpdates), "share_usage": .flag(settings.shareUsage), "crash_reports": .flag(settings.crashReports),
                "speech_model": .text(settings.speechModel.value),
            ]
        case let .siteDay(site, words, dictations):
            return ["site": .text(site.value), "words": .integer(words), "dictations": .integer(dictations)]
        }
    }

    /// One of each, so `voz telemetry` lists the fields the encoder really sends
    static let samples: [TelemetryFact] = [
        .versionPing(.update, version: "0.0.0", previous: "0.0.0"),
        .milestone(.firstDictation),
        .dailyActive(firstOfWeek: true, firstOfMonth: true, weeksSinceFirstUse: "0", words: 0, dictations: 0),
        .appDay(.app(nil), words: 0, dictations: 0),
        .latencyDay(model: .model(""), medianMs: 0, dictations: 0),
        .failureDay(.failure(.appHang), count: 0),
        .extensionDay(package: .app(nil), runs: 0),
        .extensionWeek(package: .app(nil)),
        .settingsWeek(SettingsSnapshot(
            cleanup: false, livePreview: false, insertIntoApp: false, soundCues: false, launchAtLogin: false, autoUpdate: false,
            betaUpdates: false, shareUsage: false, crashReports: false, speechModel: .model("")
        )),
        .siteDay(.site(""), words: 0, dictations: 0),
    ]
}

/// The few fields about this Mac that facts may carry. They stay coarse, because fields that never change can identify someone in a small user base.
struct TelemetryEnvironment: Equatable, Sendable {
    let version: String
    let channel: String
    let osMajor: Int
    let chipFamily: String

    static let current = TelemetryEnvironment(
        version: SystemContext.appVersion,
        channel: UpdateChannel(version: SystemContext.appVersion).rawValue,
        osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        chipFamily: chipFamily(of: SystemContext.chip)
    )

    /// `Apple M3 Pro` becomes `m3`
    static func chipFamily(of chip: String) -> String {
        let words: [Substring] = chip.split(separator: " ")
        let family = words.first { $0.count >= 2 && $0.first == "M" && $0.dropFirst().allSatisfy(\.isNumber) }
        return family?.lowercased() ?? "other"
    }
}
