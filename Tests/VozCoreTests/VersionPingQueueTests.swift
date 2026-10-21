import Testing
import VozCore

struct VersionPingQueueTests {
    @Test func retriesKeepPayloadAndAcknowledgementRemovesOnlySentPing() throws {
        let restore = makeVersionPingQueue()
        let queue = try restore()
        let (pingID, pingIDText) = makePingID()
        try queue.enqueue(.install, version: "1.0", previous: nil, pingID: pingID, projectToken: "test")
        let install = try #require(queue.pending.first)
        try queue.enqueue(.update, version: "1.1-beta.4", previous: "1.0", pingID: pingID, projectToken: "test")
        let restored = try restore()
        #expect(restored.pending.first == install)
        let payload = try decodeVersionPing(install)
        #expect(payload.event == "version_ping")
        #expect(!payload.uuid.isEmpty)
        #expect(!payload.timestamp.isEmpty)
        let update = try decodeVersionPing(#require(restored.pending.last))
        #expect(update.distinctID == pingIDText)
        #expect(payload.distinctID == pingIDText)
        #expect(payload.properties.kind == "install")
        #expect(payload.properties.channel == "stable")
        #expect(payload.properties.previous == nil)
        #expect(update.properties.channel == "beta")
        #expect(update.properties.previous == "1.0")
        #expect(!payload.properties.processPersonProfile)
        #expect(payload.properties.geoIPDisable)
        try restored.acknowledge(install)
        #expect(try restore().pending.count == 1)
        try restored.clear()
        #expect(try restore().pending.isEmpty)
    }
}

struct UpdateChannelTests {
    @Test func unstampedBuildsAreDev() {
        #expect(UpdateChannel(version: "0.0.0-dev") == .dev)
        #expect(UpdateChannel(version: "0.0.2-beta.63") == .beta)
        #expect(UpdateChannel(version: "0.0.2") == .stable)
    }
}
