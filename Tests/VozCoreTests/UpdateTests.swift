import Testing
@testable import VozCore

@Suite struct UpdateTests {
    @Test func betaVersionsBelongToTheBetaChannel() {
        #expect(UpdateChannel(version: "0.2.0-beta.41") == .beta)
        #expect(UpdateChannel(version: "0.2.0") == .stable)
    }

    @Test func firstLaunchReportsNothing() {
        #expect(UpdateDetector.installedUpdate(previousVersion: nil, currentVersion: "0.1.0") == nil)
    }

    @Test func sameVersionReportsNothing() {
        #expect(UpdateDetector.installedUpdate(previousVersion: "0.1.0", currentVersion: "0.1.0") == nil)
    }

    @Test func versionChangeReportsFromToAndChannel() {
        let event = UpdateDetector.installedUpdate(previousVersion: "0.1.0", currentVersion: "0.1.0-beta.7")
        #expect(event == .updateInstalled(from: "0.1.0", to: "0.1.0-beta.7", channel: .beta))
        #expect(event?.name == "update_installed")
        #expect(event?.properties["from"] == .version("0.1.0"))
        #expect(event?.properties["channel"] == .label("beta"))
    }
}
