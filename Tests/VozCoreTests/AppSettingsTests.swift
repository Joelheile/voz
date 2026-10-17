import Testing
@testable import VozCore

@MainActor
@Suite struct SettingsTests {
    @Test func defaults() {
        let settings = SettingsFixture().makeSettings()
        #expect(settings.hotkey == .rightCommand)
        #expect(!settings.holdToTalk)
        #expect(settings.muteWhileRecording)
        #expect(settings.copyToClipboard)
        #expect(settings.insertIntoApp)
        #expect(settings.languageMode == .automatic)
        #expect(settings.indicatorStyle == .notch)
        #expect(!settings.soundCues)
        #expect(settings.launchAtLogin)
        #expect(!settings.onboardingCompleted)
        #expect(settings.cleanupEnabled)
        #expect(settings.analyticsEnabled)
        #expect(!settings.receiveBetaUpdates)
    }

    @Test func persistsEveryKey() {
        let fixture = SettingsFixture()
        let settings = fixture.makeSettings()
        settings.hotkey = Hotkey(keyCode: 49, modifiers: [.maskControl, .maskAlternate])
        settings.holdToTalk = true
        settings.muteWhileRecording = false
        settings.copyToClipboard = false
        settings.insertIntoApp = false
        settings.languageMode = .english
        settings.indicatorStyle = .pill
        settings.soundCues = true
        settings.launchAtLogin = false
        settings.onboardingCompleted = true
        settings.cleanupEnabled = false
        settings.analyticsEnabled = false
        settings.receiveBetaUpdates = true

        let reloaded = fixture.makeSettings()
        #expect(reloaded.hotkey == settings.hotkey)
        #expect(reloaded.holdToTalk)
        #expect(!reloaded.muteWhileRecording)
        #expect(!reloaded.copyToClipboard)
        #expect(!reloaded.insertIntoApp)
        #expect(reloaded.languageMode == .english)
        #expect(reloaded.indicatorStyle == .pill)
        #expect(reloaded.soundCues)
        #expect(!reloaded.launchAtLogin)
        #expect(reloaded.onboardingCompleted)
        #expect(!reloaded.cleanupEnabled)
        #expect(!reloaded.analyticsEnabled)
        #expect(reloaded.receiveBetaUpdates)
        #expect(fixture.storedString(forKey: "languageMode") == "english")
        #expect(fixture.storedString(forKey: "indicatorStyle") == "pill")
    }

    @Test func outputFollowsToggles() {
        let settings = SettingsFixture().makeSettings()
        settings.copyToClipboard = false
        #expect(settings.output.needsClipboardRestore)
    }
}
