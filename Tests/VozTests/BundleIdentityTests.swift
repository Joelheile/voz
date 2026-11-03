import Testing
@testable import Voz

struct BundleIdentityTests {
    @Test func staysTheSameWhileTheBundleStaysInPlace() throws {
        let path = try makeTemporaryDirectory()
        defer { removeFile(atPath: path) }
        #expect(BundleIdentity(path: path) == BundleIdentity(path: path))
    }

    @Test func changesWhenAnUpdateSwapsInANewBundle() throws {
        let installed = try makeTemporaryDirectory()
        let staged = try makeTemporaryDirectory()
        defer {
            removeFile(atPath: installed)
            removeFile(atPath: staged)
        }
        let launched = BundleIdentity(path: installed)
        #expect(swapItems(atPath: installed, withItemAtPath: staged))
        #expect(BundleIdentity(path: installed) != launched)
    }

    @Test func isMissingOnceTheBundleIsGone() throws {
        let path = try makeTemporaryDirectory()
        removeFile(atPath: path)
        #expect(BundleIdentity(path: path) == nil)
    }
}
