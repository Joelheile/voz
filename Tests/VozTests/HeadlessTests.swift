import Testing
@testable import Voz

@Suite @MainActor struct HeadlessTests {
    @Test(arguments: ["0", "-1", "nan", "inf", "1e300", "61"])
    func recorderMeasurementRejectsInvalidDurations(_ seconds: String) async {
        #expect(await Headless.run(["Voz", "--measure-recorder", seconds]) == 64)
    }
}

@Suite @MainActor struct HeadlessOptionTests {
    @Test(arguments: ["0", "-1", "nan", "inf", "1e-300", "1e300"])
    func simulationRejectsInvalidSpeed(_ speed: String) async {
        #expect(await Headless.run(["Voz", "--simulate-dictation", "/missing.wav", "--speed", speed]) == 64)
    }

    @Test(arguments: [("--repeat", "0"), ("--repeat", "-1"), ("--repeat", "invalid"), ("--budget-ms", "0"), ("--budget-ms", "-1"), ("--budget-ms", "invalid")])
    func evaluationRejectsInvalidOptions(_ option: String, _ value: String) async {
        #expect(await Headless.run(["Voz", "--eval", "/missing.json", option, value]) == 64)
    }
}
