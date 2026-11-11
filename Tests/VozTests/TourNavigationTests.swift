import Testing
@testable import Voz

@MainActor
@Suite struct TourNavigationTests {
    @Test func backFromAPageOpenedInTheTourReturnsToTheSameCard() {
        let model = PopoverModel()
        model.page = .tour
        model.tourStep = .dictionary
        model.page = .dictionary
        #expect(model.page == .dictionary)
        model.goBack()
        #expect(model.page == .tour)
        #expect(model.tourStep == .dictionary)
        #expect(model.tourActive)
    }

    @Test func backGoesHomeOnceTheTourIsDone() {
        let model = PopoverModel()
        model.page = .tour
        model.finishTour()
        model.page = .dictionary
        model.goBack()
        #expect(model.page == .home)
    }

    @Test func pagesBelowSettingsKeepTheirOwnParentDuringTheTour() {
        let model = PopoverModel()
        model.page = .tour
        model.page = .privacy
        model.goBack()
        #expect(model.page == .settings)
        model.goBack()
        #expect(model.page == .tour)
    }

    @Test func leavingTheTourEndsIt() {
        let model = PopoverModel()
        model.page = .tour
        model.tourStep = .extensions
        model.goBack()
        #expect(model.page == .home)
        #expect(!model.tourActive)
        #expect(model.tourStep == .dictate)
    }

    @Test func extrasComeBeforeTryingDictation() {
        #expect(SetupStep.allCases == [.access, .languages, .model, .extras, .tryIt])
        #expect(AnalyticsEvent.setupStepViewed(.extras).milestone == .setupExtras)
    }
}
