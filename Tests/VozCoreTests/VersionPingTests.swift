import Testing
@testable import VozCore

struct VersionPingTests {
    @Test func newInstallPingsInstall() {
        #expect(VersionPing.kind(isNewInstall: true, previousVersion: nil, currentVersion: "1.2.0") == .install)
    }

    @Test func changedVersionPingsUpdate() {
        #expect(VersionPing.kind(isNewInstall: false, previousVersion: "1.1.0", currentVersion: "1.2.0") == .update)
    }

    @Test func sameVersionOrUnknownPreviousSendsNothing() {
        #expect(VersionPing.kind(isNewInstall: false, previousVersion: "1.2.0", currentVersion: "1.2.0") == nil)
        #expect(VersionPing.kind(isNewInstall: false, previousVersion: nil, currentVersion: "1.2.0") == nil)
    }

    @Test func bodyCarriesVersionAndNoStableID() throws {
        let first = try String(decoding: VersionPing.update.body(version: "1.2.0", projectToken: "token"), as: UTF8.self)
        let second = try String(decoding: VersionPing.update.body(version: "1.2.0", projectToken: "token"), as: UTF8.self)
        #expect(first.contains(#""version":"1.2.0""#))
        #expect(first.contains(#""kind":"update""#))
        #expect(first.contains(#""$process_person_profile":false"#))
        #expect(first != second)
    }
}
