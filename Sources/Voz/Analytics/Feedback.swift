import Foundation

/// A message you send from the menu or `voz feedback`. It lands as a response to the "Voz feedback" API survey in PostHog, under a new random ID each time, so it is never tied to this Mac or to usage stats.
struct Feedback {
    static let surveyID = "01a199e8-ed38-0000-21da-f54ba7a0fbf1"
    static let messageQuestionID = "7fd3cc3e-c2a3-4fc4-8a3f-68da43508280"
    static let emailQuestionID = "e8789b8c-141b-4b2d-b305-082ec0b65dc3"
    private static let endpoint = URL(string: "\(Analytics.host)/i/v0/e/")!

    let message: String
    let email: String
    let speechModel: String

    init(message: String, email: String, speechModel: String) {
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.speechModel = speechModel
    }

    var isEmpty: Bool { message.isEmpty }

    func body(projectToken: String) throws -> Data {
        let properties = Properties(message: message, email: email.isEmpty ? nil : email, speechModel: speechModel)
        return try CapturePayload(event: "survey sent", distinctID: UUID(), properties: properties, projectToken: projectToken).encoded()
    }

    func send() async throws {
        guard SystemContext.isOfficialBuild else { throw FeedbackError.unofficialBuild }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body(projectToken: Analytics.projectToken)
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw FeedbackError.rejected(status: status) }
    }

    private struct Question: Encodable {
        let id: String
        let question: String
    }

    private struct Properties: Encodable {
        let surveyID = Feedback.surveyID
        let submissionID = UUID().uuidString
        let completed = true
        let questions = [
            Question(id: Feedback.messageQuestionID, question: "What should we know?"),
            Question(id: Feedback.emailQuestionID, question: "Email, if you want a reply"),
        ]
        let message: String
        let email: String?
        let speechModel: String
        let appVersion = SystemContext.appVersion
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let processPersonProfile = false
        let geoIPDisable = true

        enum CodingKeys: String, CodingKey {
            case surveyID = "$survey_id"
            case submissionID = "$survey_submission_id"
            case completed = "$survey_completed"
            case questions = "$survey_questions"
            case message = "$survey_response_7fd3cc3e-c2a3-4fc4-8a3f-68da43508280"
            case email = "$survey_response_e8789b8c-141b-4b2d-b305-082ec0b65dc3"
            case speechModel = "speech_model"
            case appVersion = "app_version"
            case osVersion = "os_version"
            case processPersonProfile = "$process_person_profile"
            case geoIPDisable = "$geoip_disable"
        }
    }
}

enum FeedbackError: LocalizedError {
    case unofficialBuild
    case rejected(status: Int)

    var errorDescription: String? {
        switch self {
        case .unofficialBuild: "This build of Voz can't send feedback. Open an issue at github.com/Joelheile/voz instead."
        case .rejected(let status): "PostHog turned the feedback away with status \(status). Try again in a minute."
        }
    }
}
