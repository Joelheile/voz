import Testing
@testable import Voz

@MainActor
@Test func clearingAGrantResetsOnlyVozsOwnEntryForThatService() {
    let expected: [(Permissions.PrivacyPane, String)] = [
        (.microphone, "Microphone"),
        (.accessibility, "Accessibility"),
        (.inputMonitoring, "ListenEvent"),
        (.systemAudio, "AudioCapture"),
    ]
    for (pane, service) in expected {
        #expect(StaleGrant.arguments(for: pane, bundleID: "com.joelheile.voz") == ["reset", service, "com.joelheile.voz"])
    }
}
