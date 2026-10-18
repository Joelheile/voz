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
        #expect(settings.speechModel == .parakeetUltra)
        #expect(settings.indicatorStyle == .notch)
        #expect(!settings.soundCues)
        #expect(settings.launchAtLogin)
        #expect(!settings.onboardingCompleted)
        #expect(settings.cleanupEnabled)
        #expect(!settings.analyticsEnabled)
        #expect(!settings.receiveBetaUpdates)
        #expect(settings.versionPingEnabled)
    }

    @Test func editedCleanupPromptPersistsAndResettingFollowsTheBuiltInPrompt() {
        let fixture = SettingsFixture()
        let settings = fixture.makeSettings()
        #expect(settings.cleanupPrompt == CleanupPrompt.standard)
        settings.cleanupPrompt = "Only fix punctuation."
        #expect(fixture.makeSettings().cleanupPrompt == "Only fix punctuation.")
        settings.cleanupPrompt = CleanupPrompt.standard
        #expect(fixture.storedString(forKey: SettingsKey.cleanupPrompt) == nil)
    }

    @Test func persistsEveryKey() {
        let fixture = SettingsFixture()
        let settings = fixture.makeSettings()
        settings.hotkey = Hotkey(keyCode: 49, modifiers: [.maskControl, .maskAlternate])
        settings.holdToTalk = true
        settings.muteWhileRecording = false
        settings.copyToClipboard = false
        settings.insertIntoApp = false
        settings.speechModel = .parakeetV2
        settings.indicatorStyle = .pill
        settings.soundCues = true
        settings.launchAtLogin = false
        settings.onboardingCompleted = true
        settings.cleanupEnabled = false
        settings.analyticsEnabled = true
        settings.receiveBetaUpdates = true

        let reloaded = fixture.makeSettings()
        #expect(reloaded.hotkey == settings.hotkey)
        #expect(reloaded.holdToTalk)
        #expect(!reloaded.muteWhileRecording)
        #expect(!reloaded.copyToClipboard)
        #expect(!reloaded.insertIntoApp)
        #expect(reloaded.speechModel == .parakeetV2)
        #expect(reloaded.indicatorStyle == .pill)
        #expect(reloaded.soundCues)
        #expect(!reloaded.launchAtLogin)
        #expect(reloaded.onboardingCompleted)
        #expect(!reloaded.cleanupEnabled)
        #expect(reloaded.analyticsEnabled)
        #expect(reloaded.receiveBetaUpdates)
        #expect(fixture.storedString(forKey: "speechModel") == "parakeet-tdt-v2")
        #expect(fixture.storedString(forKey: "indicatorStyle") == "pill")
    }

    @Test func removedSpeechModelFallsBackToUltra() {
        let fixture = SettingsFixture()
        fixture.store("parakeet-redux", forKey: "speechModel")
        #expect(fixture.makeSettings().speechModel == .parakeetUltra)
    }

    @Test func outputFollowsToggles() {
        let settings = SettingsFixture().makeSettings()
        settings.copyToClipboard = false
        #expect(settings.output.needsClipboardRestore)
    }
}
