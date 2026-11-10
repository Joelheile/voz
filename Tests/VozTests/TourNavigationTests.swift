import Testing
@testable import Voz

@MainActor
@Suite struct TourNavigationTests {
    @Test func backFromAPageOpenedInTheTourReturnsToTheSameCard() {
        let model = PopoverModel()
        model.startTour()
        model.tourStep = .dictionary
        model.openFromTour(.dictionary)
        #expect(model.page == .dictionary)
        model.goBack()
        #expect(model.page == .tour)
        #expect(model.tourStep == .dictionary)
        #expect(model.tourActive)
    }

    @Test func backFromThatPageOpenedNormallyStillGoesHome() {
        let model = PopoverModel()
        model.startTour()
        model.openFromTour(.dictionary)
        model.goBack()
        model.page = .dictionary
        model.goBack()
        #expect(model.page == .home)
    }

    @Test func leavingTheTourEndsIt() {
        let model = PopoverModel()
        model.startTour()
        model.tourStep = .extensions
        model.goBack()
        #expect(model.page == .home)
        #expect(!model.tourActive)
        #expect(model.tourStep == .dictate)
    }

    @Test func holdModeIsLabelledWithBothGestures() {
        #expect(TalkMode.allCases.map(\.rawValue) == ["Tap", "Tap or hold"])
    }

    @Test func extrasComeBeforeTryingDictation() {
        #expect(SetupStep.allCases == [.access, .languages, .model, .extras, .tryIt])
        #expect(AnalyticsEvent.setupStepViewed(.extras).milestone == .setupExtras)
    }
}
