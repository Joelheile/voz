import Sparkle
import VozCore

@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private let settings: AppSettings
    private var controller: SPUStandardUpdaterController?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated { settings.receiveBetaUpdates ? [UpdateChannel.beta.rawValue] : [] }
    }
}
