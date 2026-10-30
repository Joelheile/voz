import Testing
@testable import Voz

@Suite @MainActor struct HeadlessTests {
    @Test func appleSpeechRejectsEmptyAudioBeforeLoadingAssets() async {
        await #expect(throws: AppleSpeechError.emptyAudio) {
            try await AppleSpeechTranscriber().transcribe([], locale: SpeechEngine.locale, vocabulary: [])
        }
    }
}
