import Testing
@testable import Voz

@MainActor @Suite struct AIModelsTests {
    @Test func aFreshInstallAsksWhichModelToUseUntilYouPickOne() async {
        let settings = AppSettings(defaults: makeDefaults(), home: temporaryHome())
        #expect(!settings.hasPickedAIModel)
        #expect(settings.aiModel == .apple)
        await AIModels.useApple(settings)
        #expect(settings.hasPickedAIModel)
    }

    @Test func thePickCardLeadsWithChatGPT() {
        #expect(AIModels.pickCard.buttons.last == AIModels.chatGPTButton)
    }
}
