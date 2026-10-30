import CoreGraphics
import Foundation
import Sparkle

@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private static let idleBeforeInstall: TimeInterval = 600
    private static let idleCheckInterval: TimeInterval = 60

    private let settings: AppSettings
    private let isBusy: () -> Bool
    private var controller: SPUStandardUpdaterController?
    private var pendingInstall: (() -> Void)?
    private var installWhenIdle: (() -> Void)?
    private var idleCheck: Timer?

    init(settings: AppSettings, isBusy: @escaping () -> Bool) {
        self.settings = settings
        self.isBusy = isBusy
        super.init()
    }

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    func checkForUpdates() {
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

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installWhenIdle = immediateInstallHandler
        idleCheck?.invalidate()
        idleCheck = Timer.scheduledTimer(withTimeInterval: Self.idleCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.installIfIdle() }
        }
        return true
    }

    private func installIfIdle() {
        guard !isBusy(), Self.userIdleSeconds >= Self.idleBeforeInstall, let install = installWhenIdle else { return }
        idleCheck?.invalidate()
        idleCheck = nil
        installWhenIdle = nil
        install()
    }

    private static var userIdleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
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

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        LaunchAgent.bootOut()
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
