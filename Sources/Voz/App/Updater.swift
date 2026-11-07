import CoreGraphics
import Foundation
import Sparkle

@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    /// The version a scheduled check found, shown in the menu until the update session ends.
    @Published private(set) var availableVersion: String?

    private let settings: AppSettings
    private let isBusy: () -> Bool
    private let showNotice: (UpdateNotice) async -> Bool
    private var controller: SPUStandardUpdaterController?
    private var pendingInstall: (() -> Void)?
    private var installDownloaded: (() -> Void)?
    /// Set when a scheduled check found the update, so a window you opened yourself gets no notice on top
    private var foundInBackground = false
    private var tick: Timer?

    init(settings: AppSettings, isBusy: @escaping () -> Bool, showNotice: @escaping (UpdateNotice) async -> Bool) {
        self.settings = settings
        self.isBusy = isBusy
        self.showNotice = showNotice
        super.init()
    }

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        tick = Timer.scheduledTimer(withTimeInterval: IdleInstall.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkOnWaitingUpdate() }
        }
    }

    /// Installs an update that already downloaded, or checks for one.
    func checkForUpdates() {
        guard installDownloaded == nil else { return installNow() }
        controller?.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        controller?.updater.checkForUpdatesInBackground()
    }

    func resumePendingInstall() {
        guard !isBusy(), let install = pendingInstall else { return }
        pendingInstall = nil
        install()
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isBusy() else { return false }
        pendingInstall = installHandler
        return true
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updatesInBackground, !UpdateChannel(version: SystemContext.appVersion).checksInBackground else { return }
        throw DevBuildSkipsBackgroundUpdates()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        settings.receiveBetaUpdates ? [UpdateChannel.beta.rawValue] : []
    }

    /// Holds a silently downloaded update and installs it once you step away, so a restart never interrupts you.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        availableVersion = item.displayVersionString
        installDownloaded = immediateInstallHandler
        foundInBackground = true
        return true
    }

    private func checkOnWaitingUpdate() {
        resumePendingInstall()
        let busy = isBusy()
        let secondsSinceInput = IdleInstall.secondsSinceInput()
        if installDownloaded != nil, IdleInstall.isDue(busy: busy, secondsSinceInput: secondsSinceInput) { return installNow() }
        offerUpdate(busy: busy, secondsSinceInput: secondsSinceInput)
    }

    private func offerUpdate(busy: Bool, secondsSinceInput: TimeInterval) {
        let defaults = UserDefaults.standard
        let now = Date()
        let lastShown = defaults.object(forKey: UpdateNotice.lastShownKey) as? Date
        guard foundInBackground, let version = availableVersion,
              UpdateNotice.isDue(busy: busy, secondsSinceInput: secondsSinceInput, lastShown: lastShown, now: now) else { return }
        defaults.set(now, forKey: UpdateNotice.lastShownKey)
        let notice = UpdateNotice(version: version, isDownloaded: installDownloaded != nil)
        Task {
            if await showNotice(notice) { checkForUpdates() }
        }
    }

    private func installNow() {
        let install = installDownloaded
        installDownloaded = nil
        install?()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// With automatic installs off, scheduled checks only offer the update in the menu, so Sparkle never replaces voz behind your back.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        foundInBackground = !handleShowingUpdate
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        foundInBackground = false
    }
}

/// Tells you about a waiting update when you're at your Mac and between things. Voz stays out of the way otherwise, and the update waits in the menu.
struct UpdateNotice: Equatable {
    static let later = "Later"
    static let lastShownKey = "updateNoticeShownAt"
    static let repeatAfter: TimeInterval = 24 * 60 * 60
    /// Input this recent means you're mid-keystroke
    static let quietFor: TimeInterval = 3
    /// No input for this long means nobody would see it
    static let presentWithin: TimeInterval = 5 * 60

    let title: String
    let action: String

    init(version: String, isDownloaded: Bool) {
        // A beta's build number would make the one-line notice too wide
        let shortVersion = version.replacing(/-beta\.\d+/, with: " beta")
        title = isDownloaded ? "Voz \(shortVersion) is ready" : "Voz \(shortVersion) is available"
        action = isDownloaded ? "Restart to update" : "See what's new"
    }

    static func isDue(busy: Bool, secondsSinceInput: TimeInterval, lastShown: Date?, now: Date) -> Bool {
        guard !busy, secondsSinceInput >= quietFor, secondsSinceInput < presentWithin else { return false }
        guard let lastShown else { return true }
        return now.timeIntervalSince(lastShown) >= repeatAfter
    }
}

enum RestartGuard {
    /// A restart ends a live meeting and drops a question an extension is waiting on, the same as it would lose a dictation
    static func blocksRestart(dictating: Bool, runningActivities: Int, asking: Bool) -> Bool {
        dictating || runningActivities > 0 || asking
    }
}

enum IdleInstall {
    static let checkInterval: TimeInterval = 60
    static let awayAfter: TimeInterval = 10 * 60

    static func isDue(busy: Bool, secondsSinceInput: TimeInterval) -> Bool {
        !busy && secondsSinceInput >= awayAfter
    }

    static func secondsSinceInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}

struct DevBuildSkipsBackgroundUpdates: LocalizedError {
    var errorDescription: String? { "Dev builds check for updates only when you ask." }
}

struct LaunchVersion {
    private static let key = "lastLaunchedVersion"

    let current: String
    let updatedFrom: String?

    /// Dev builds share defaults with the installed app, so they leave the last version alone.
    static func record(_ current: String, in defaults: UserDefaults) -> LaunchVersion {
        guard UpdateChannel(version: current) != .dev else { return LaunchVersion(current: current, updatedFrom: nil) }
        let previous = defaults.string(forKey: key)
        defaults.set(current, forKey: key)
        return LaunchVersion(current: current, updatedFrom: previous == current ? nil : previous)
    }
}
