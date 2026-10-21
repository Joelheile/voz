import Sparkle
import VozCore

@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private let settings: AppSettings
    private let isBusy: () -> Bool
    private var controller: SPUStandardUpdaterController?
    private var pendingInstall: (() -> Void)?

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

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        settings.receiveBetaUpdates ? [UpdateChannel.beta.rawValue] : []
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        LaunchAgent.bootOut()
    }
}
