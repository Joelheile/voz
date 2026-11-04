import CoreGraphics
import Foundation
import Sparkle

@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    /// The version a scheduled check found, shown in the menu until the update session ends.
    @Published private(set) var availableVersion: String?

    private let settings: AppSettings
    private let isBusy: () -> Bool
    private var controller: SPUStandardUpdaterController?
    private var pendingInstall: (() -> Void)?
    private var installDownloaded: (() -> Void)?
    private var idleCheck: Timer?

    init(settings: AppSettings, isBusy: @escaping () -> Bool) {
        self.settings = settings
        self.isBusy = isBusy
        super.init()
    }

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
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
        idleCheck?.invalidate()
        idleCheck = Timer.scheduledTimer(withTimeInterval: IdleInstall.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.installIfAway() }
        }
        return true
    }

    private func installIfAway() {
        guard IdleInstall.isDue(busy: isBusy(), secondsSinceInput: IdleInstall.secondsSinceInput()) else { return }
        installNow()
    }

    private func installNow() {
        idleCheck?.invalidate()
        idleCheck = nil
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
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
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
