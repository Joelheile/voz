import Testing
import VozCore

struct VersionPingQueueTests {
    @Test func retriesKeepPayloadAndAcknowledgementRemovesOnlySentPing() throws {
        let restore = makeVersionPingQueue()
        let queue = try restore()
        try queue.enqueue(.install, version: "1.0", projectToken: "test")
        let install = try #require(queue.pending.first)
        try queue.enqueue(.update, version: "1.1", projectToken: "test")
        let restored = try restore()
        #expect(restored.pending.first == install)
        let payload = try decodeVersionPing(install)
        #expect(payload.event == "version_ping")
        #expect(!payload.uuid.isEmpty)
        #expect(!payload.timestamp.isEmpty)
        let update = try decodeVersionPing(#require(restored.pending.last))
        #expect(update.distinctID != payload.distinctID)
        #expect(payload.properties.kind == "install")
        #expect(!payload.properties.processPersonProfile)
        #expect(payload.properties.geoIPDisable)
        try restored.acknowledge(install)
        #expect(try restore().pending.count == 1)
        try restored.clear()
        #expect(try restore().pending.isEmpty)
    }
}
