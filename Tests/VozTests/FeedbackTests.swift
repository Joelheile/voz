import Testing
@testable import Voz

struct FeedbackTests {
    @Test func feedbackIsAnAnonymousResponseToTheVozFeedbackSurvey() throws {
        let feedback = Feedback(message: "  The hotkey misses short words  ", email: "me@example.com", speechModel: "parakeet")
        let first = try #require(try decodeJSON(feedback.body(projectToken: "test")).object)
        let second = try #require(try decodeJSON(feedback.body(projectToken: "test")).object)
        let properties = try #require(first["properties"]?.object)
        #expect(first["event"] == .string("survey sent"))
        #expect(properties["$survey_id"] == .string("01a199e8-ed38-0000-21da-f54ba7a0fbf1"))
        #expect(properties["$survey_response_7fd3cc3e-c2a3-4fc4-8a3f-68da43508280"] == .string("The hotkey misses short words"))
        #expect(properties["$survey_response_e8789b8c-141b-4b2d-b305-082ec0b65dc3"] == .string("me@example.com"))
        #expect(properties["$process_person_profile"] == .bool(false))
        #expect(first["distinct_id"] != second["distinct_id"])
        #expect(properties["$survey_submission_id"] != second["properties"]?.object?["$survey_submission_id"])
    }
}
