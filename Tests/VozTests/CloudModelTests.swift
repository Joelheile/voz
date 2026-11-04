import Testing
@testable import Voz

struct CloudModelTests {
    private func params(_ model: String? = nil, effort: ModelEffort? = nil) -> GenerateParams {
        let schema = GenerationSpec.object([.init(name: "text", schema: .string("The reply"), optional: false)])
        return GenerateParams(call: 1, prompt: "Anna: lunch at 1?", instructions: "Reply as Joel", schema: schema, model: model, effort: effort, deadline: 0)
    }

    private let claude = CloudModel.claudeModelList(.object(["data": .array(
        ["claude-haiku-4-5-20251001", "claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-4-8", "claude-opus-5-5", "claude-fable-5-1"]
            .map { .object(["id": .string($0), "display_name": .string($0)]) }
    )]))

    private let chatGPT = CloudModel.chatGPTModelList(.object(["models": .array([
        .object(["slug": .string("gpt-6.1-sol"), "display_name": .string("GPT-6.1 Sol"), "visibility": .string("list")]),
        .object(["slug": .string("gpt-6-sol"), "display_name": .string("GPT-6 Sol"), "visibility": .string("list")]),
        .object(["slug": .string("gpt-6.1-terra"), "display_name": .string("GPT-6.1 Terra"), "visibility": .string("list")]),
        .object(["slug": .string("gpt-6-luna"), "display_name": .string("GPT-6 Luna"), "visibility": .string("list")]),
        .object(["slug": .string("gpt-6-astra"), "display_name": .string("GPT-6 Astra"), "visibility": .string("hide")]),
    ])]))

    private func model(_ id: String) -> AIModelInfo {
        AIModelInfo(id: id, name: id, tier: ModelTier(modelID: id))
    }

    @Test func tiersRunTheNewestModelOfTheirFamily() throws {
        #expect(try CloudModel.resolve("fast", in: claude).id == "claude-haiku-5-5")
        #expect(try CloudModel.resolve(nil, in: claude).id == "claude-sonnet-5-5")
        #expect(try CloudModel.resolve("strong", in: claude).id == "claude-opus-5-5")
        #expect(try CloudModel.resolve("max", in: claude).id == "claude-fable-5-1")
        #expect(try CloudModel.resolve("strong", in: chatGPT).id == "gpt-6.1-sol")
        #expect(try CloudModel.resolve("claude-opus-4-8", in: claude).id == "claude-opus-4-8")
    }

    @Test func anotherProvidersModelRunsAsTheSameTier() throws {
        #expect(try CloudModel.resolve("claude-opus-5-5", in: chatGPT).id == "gpt-6.1-sol")
        #expect(try CloudModel.resolve("gpt-6-luna", in: claude).id == "claude-haiku-5-5")
        #expect(throws: CloudModelError.failed("This account has no max model. Run voz models to see what it has")) {
            try CloudModel.resolve("max", in: chatGPT)
        }
        #expect(throws: CloudModelError.failed("No model \"gemini-3\". Pass fast, balanced, strong, max or an ID from ctx.models()")) {
            try CloudModel.resolve("gemini-3", in: chatGPT)
        }
    }

    @Test func modelListShowsWhatEachTierRuns() {
        let list = AIModelList(provider: .chatgpt, models: chatGPT)
        #expect(list.tiers == ["fast": "gpt-6-luna", "balanced": "gpt-6.1-terra", "strong": "gpt-6.1-sol"])
        #expect(!list.models.contains { $0.id == "gpt-6-astra" })
    }

    private func lines(_ events: [String]) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    @Test func claudeThinksOnlyWhenTheExtensionAsksForEffort() throws {
        let fast = try #require(CloudModel.claudeBody(params(), model: model("claude-haiku-5-5")).object)
        #expect(fast["model"] == .string("claude-haiku-5-5"))
        #expect(fast["thinking"] == .object(["type": .string("disabled")]))
        #expect(fast["system"] == .string("Reply as Joel"))
        let format = try #require(fast["output_config"]?.object?["format"]?.object)
        #expect(format["schema"]?.object?["additionalProperties"] == .bool(false))
        #expect(format["schema"]?.object?["required"] == .array([.string("text")]))

        let opus = try #require(CloudModel.claudeBody(params(effort: .high), model: model("claude-opus-5-5")).object)
        #expect(opus["model"] == .string("claude-opus-5-5"))
        #expect(opus["thinking"] == nil)
        #expect(opus["output_config"]?.object?["effort"] == .string("high"))
    }

    @Test func claudeReplyGivesTheTextBlockOrSaysWhyNot() throws {
        let reply = JSONValue.object(["stop_reason": .string("end_turn"), "content": .array([.object(["type": .string("text"), "text": .string("{\"text\":\"Sure\"}")])])])
        #expect(try CloudModel.claudeText(reply) == "{\"text\":\"Sure\"}")
        #expect(throws: CloudModelError.failed("Claude declined to write this")) {
            try CloudModel.claudeText(.object(["stop_reason": .string("refusal"), "content": .array([])]))
        }
    }

    @Test func chatGPTStreamsWithoutStoringAndLeavesOutUnsupportedFields() throws {
        let fast = try #require(CloudModel.chatGPTBody(params(), model: model("gpt-6.1-terra")).object)
        #expect(fast["model"] == .string("gpt-6.1-terra"))
        #expect(fast["reasoning"] == .object(["effort": .string("none")]))
        #expect(fast["store"] == .bool(false))
        #expect(fast["stream"] == .bool(true))
        #expect(fast["instructions"] == .string("Reply as Joel"))
        for unsupported in ["temperature", "max_output_tokens", "metadata", "previous_response_id"] { #expect(fast[unsupported] == nil) }

        let sol = try #require(CloudModel.chatGPTBody(params(), model: model("gpt-6.1-sol")).object)
        #expect(sol["reasoning"] == .object(["effort": .string("low")]), "Sol doesn't support none")
        let thinking = try #require(CloudModel.chatGPTBody(params(effort: .medium), model: model("gpt-6.1-terra")).object)
        #expect(thinking["reasoning"] == .object(["effort": .string("medium")]))
    }

    @Test func chatGPTTextCountsOnlyOnceTheResponseCompletes() async throws {
        let text = try await CloudModel.chatGPTText(lines([
            "event: response.output_text.delta",
            #"data: {"type":"response.output_text.delta","delta":"{\"text\":"}"#,
            #"data: {"type":"response.output_text.delta","delta":"\"Sure\"}"}"#,
            "",
            #"data: {"type":"response.completed","response":{}}"#,
        ]))
        #expect(text == "{\"text\":\"Sure\"}")

        await #expect(throws: CloudModelError.failed("ChatGPT's reply ended early. Try again")) {
            try await CloudModel.chatGPTText(lines([#"data: {"type":"response.output_text.delta","delta":"half"}"#]))
        }
    }

    @Test func usageLimitMidStreamTellsYouWhatToDo() async throws {
        let failed = #"data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#
        await #expect(throws: CloudModel.chatGPTError(code: "subscription_sharing_usage_limit_exceeded")) {
            try await CloudModel.chatGPTText(lines([failed]))
        }
        #expect(CloudModel.chatGPTError(code: "subscription_sharing_usage_limit_exceeded").localizedDescription.contains("limit you set for Voz"))
    }

    @Test func signInKeepsTheEmailOnlyWhenTheIDTokenAndScopesCheckOut() throws {
        let claims = #"{"iss":"https://auth.openai.com","aud":"oaiapp_1","nonce":"n1","exp":4102444800,"email":"joel@example.com"}"#
        func tokens(scope: String = "openid email offline_access resource.invoke chatgpt.tokens.use.direct", claims: String = claims) -> [String: JSONValue] {
            ["access_token": .string("a"), "refresh_token": .string("r"), "id_token": .string(fakeIDToken(claims)), "expires_in": .number(3600), "scope": .string(scope)]
        }
        let credentials = try ChatGPTAccount.credentials(from: tokens(), clientID: "oaiapp_1", nonce: "n1", now: epoch(0))
        #expect(credentials.email == "joel@example.com")
        #expect(credentials.expiresAt == epoch(3600))

        #expect(throws: CloudModelError.rejected("ChatGPT didn't allow Voz to use your plan. Sign in again and allow it")) {
            try ChatGPTAccount.credentials(from: tokens(scope: "openid email"), clientID: "oaiapp_1", nonce: "n1", now: epoch(0))
        }
        for (clientID, nonce) in [("oaiapp_2", "n1"), ("oaiapp_1", "n2")] {
            #expect(throws: CloudModelError.failed("ChatGPT's sign-in didn't check out. Try again")) {
                try ChatGPTAccount.credentials(from: tokens(), clientID: clientID, nonce: nonce, now: epoch(0))
            }
        }
    }

    @Test func formValuesAreFullyEncoded() {
        #expect(ChatGPTAccount.formEncoded([("redirect_uri", "http://127.0.0.1:1455/auth/callback"), ("scope", "openid email")])
            == "redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback&scope=openid%20email")
    }
}
