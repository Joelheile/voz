import Foundation

/// Which model `ctx.generate` uses. Apple's runs on your Mac. The others use a plan or credits you already have
enum AIProvider: String, CaseIterable, Sendable {
    case apple
    case chatgpt
    case claude

    static let defaultsKey = "aiModel"

    static var current: AIProvider {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AIProvider.init) ?? .apple
    }

    var name: String {
        switch self {
        case .apple: "Apple"
        case .chatgpt: "ChatGPT"
        case .claude: "Claude"
        }
    }
}

/// Four tiers every provider fills, so an extension works whichever model the user picked
enum ModelTier: String, CaseIterable, Codable, Sendable {
    case fast
    case balanced
    case strong
    case max

    static let standard = ModelTier.balanced

    private static let families: [(ModelTier, Set<String>)] = [
        (.fast, ["luna", "haiku"]),
        (.balanced, ["terra", "sonnet"]),
        (.strong, ["sol", "opus"]),
        (.max, ["astra", "fable"]),
    ]

    /// The tier a model ID belongs to, by family name: claude-opus-5-5 and gpt-6.1-sol are both strong
    init?(modelID: String) {
        let words = Set(modelID.lowercased().split { !$0.isLetter }.map(String.init))
        guard let tier = Self.families.first(where: { !$0.1.isDisjoint(with: words) })?.0 else { return nil }
        self = tier
    }
}

enum ModelEffort: String, Decodable, Sendable {
    case low
    case medium
    case high
}

struct AIModelInfo: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let tier: ModelTier?
}

/// What `ctx.models()` and `voz models` show: every model the user's account offers, and which one each tier runs
struct AIModelList: Encodable, Sendable {
    let provider: String
    let tiers: [String: String]
    let models: [AIModelInfo]

    init(provider: AIProvider, models: [AIModelInfo]) {
        self.provider = provider.rawValue
        self.models = models
        tiers = Dictionary(uniqueKeysWithValues: ModelTier.allCases.compactMap { tier in
            (try? CloudModel.resolve(tier.rawValue, in: models)).map { (tier.rawValue, $0.id) }
        })
    }
}

enum CloudModelError: Error, LocalizedError, Equatable {
    case rejected(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .rejected(let message), .failed(let message): message
        }
    }
}

/// Requests and replies for the cloud models, kept apart from the network so tests can check them
enum CloudModel {
    static let claudeKeyAccount = "claude"

    /// Picks the model for a tier name or an exact ID. An ID from another provider runs as the same tier here
    static func resolve(_ requested: String?, in models: [AIModelInfo]) throws -> AIModelInfo {
        let requested = requested ?? ModelTier.standard.rawValue
        if let exact = models.first(where: { $0.id == requested }) { return exact }
        guard let tier = ModelTier(rawValue: requested) ?? ModelTier(modelID: requested) else {
            throw CloudModelError.failed("No model \"\(requested)\". Pass fast, balanced, strong, max or an ID from ctx.models()")
        }
        guard let newest = models.filter({ $0.tier == tier }).max(by: { version($0.id).lexicographicallyPrecedes(version($1.id)) }) else {
            throw CloudModelError.failed("This account has no \(tier.rawValue) model. Run voz models to see what it has")
        }
        return newest
    }

    private static func version(_ id: String) -> [Int] {
        id.split { !$0.isNumber }.compactMap { Int($0) }
    }

    static func claudeBody(_ params: GenerateParams, model: AIModelInfo) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "max_tokens": .number(8000),
            "messages": .array([.object(["role": .string("user"), "content": .string(params.prompt)])]),
            "output_config": .object([
                "effort": .string(params.effort?.rawValue ?? "low"),
                "format": .object(["type": .string("json_schema"), "schema": params.schema.jsonSchema]),
            ]),
        ]
        if model.tier == .fast, params.effort == nil { body["thinking"] = .object(["type": .string("disabled")]) }
        if let instructions = params.instructions { body["system"] = .string(instructions) }
        return .object(body)
    }

    static func claudeText(_ reply: JSONValue) throws -> String {
        let fields = reply.object ?? [:]
        switch fields["stop_reason"]?.string {
        case "refusal": throw CloudModelError.failed("Claude declined to write this")
        case "max_tokens": throw CloudModelError.failed("Claude's reply was too long and got cut off")
        default: break
        }
        guard case .array(let blocks)? = fields["content"],
              let text = blocks.lazy.compactMap({ $0.object }).first(where: { $0["type"]?.string == "text" })?["text"]?.string
        else { throw CloudModelError.failed("Claude sent no text") }
        return text
    }

    static func chatGPTBody(_ params: GenerateParams, model: AIModelInfo) -> JSONValue {
        let lowest = [.fast, .balanced].contains(model.tier) ? "none" : "low"
        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "input": .array([.object(["role": .string("user"), "content": .string(params.prompt)])]),
            "reasoning": .object(["effort": .string(params.effort?.rawValue ?? lowest)]),
            "text": .object(["format": .object([
                "type": .string("json_schema"),
                "name": .string("result"),
                "schema": params.schema.jsonSchema,
                "strict": .bool(false),
            ])]),
            "store": .bool(false),
            "stream": .bool(true),
        ]
        if let instructions = params.instructions { body["instructions"] = .string(instructions) }
        return .object(body)
    }

    /// Reads a Responses stream. The text counts only once `response.completed` arrives
    static func chatGPTText(_ lines: some AsyncSequence<String, any Error>) async throws -> String {
        var text = ""
        for try await line in lines {
            guard line.hasPrefix("data:"),
                  let event = try? JSONDecoder().decode(JSONValue.self, from: Data(line.dropFirst(5).utf8)).object
            else { continue }
            switch event["type"]?.string {
            case "response.output_text.delta":
                text += event["delta"]?.string ?? ""
            case "response.completed":
                return text
            case "response.failed":
                throw chatGPTError(code: event["response"]?.object?["error"]?.object?["code"]?.string)
            case "response.incomplete":
                throw CloudModelError.failed("ChatGPT stopped before it finished")
            case "error":
                throw chatGPTError(code: event["code"]?.string)
            default:
                continue
            }
        }
        throw CloudModelError.failed("ChatGPT's reply ended early. Try again")
    }

    static func chatGPTError(code: String?) -> CloudModelError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded":
            .rejected("You reached the ChatGPT limit you set for Voz. Raise it in ChatGPT settings, or switch to Apple in Voz settings")
        case "subscription_sharing_usage_unavailable":
            .rejected("Your ChatGPT plan can't be used right now. Try again later, or switch to Apple in Voz settings")
        default:
            .failed("ChatGPT failed\(code.map { " (\($0))" } ?? ""). Try again")
        }
    }

    // MARK: Network

    static func generateWithClaude(_ params: GenerateParams) async throws -> String {
        let key = try claudeKey()
        let model = try resolve(params.model, in: try await ModelLists.shared.models(for: .claude))
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(claudeBody(params, model: model))
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw claudeHTTPError(status: status, body: data) }
        return try claudeText(JSONDecoder().decode(JSONValue.self, from: data))
    }

    static func claudeKey() throws -> String {
        guard let key = try Keychain.read(claudeKeyAccount).map({ String(decoding: $0, as: UTF8.self) }) else {
            throw CloudModelError.rejected("Add your Claude API key: voz ai claude -")
        }
        return key
    }

    /// Lists the models a key can use. Costs nothing, so Voz also uses it to check a key before saving it
    static func claudeModels(key: String) async throws -> [AIModelInfo] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1000")!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw claudeHTTPError(status: status, body: data) }
        return claudeModelList(try JSONDecoder().decode(JSONValue.self, from: data))
    }

    static func claudeModelList(_ reply: JSONValue) -> [AIModelInfo] {
        guard case .array(let items)? = reply.object?["data"] else { return [] }
        return items.compactMap(\.object).compactMap { item in
            item["id"]?.string.map { AIModelInfo(id: $0, name: item["display_name"]?.string ?? $0, tier: ModelTier(modelID: $0)) }
        }
    }

    static func chatGPTModels() async throws -> [AIModelInfo] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(try await ChatGPTAccount.shared.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw chatGPTHTTPError(status: status, body: data) }
        return chatGPTModelList(try JSONDecoder().decode(JSONValue.self, from: data))
    }

    /// Keeps the models ChatGPT shows in its own picker, in its order
    static func chatGPTModelList(_ reply: JSONValue) -> [AIModelInfo] {
        guard case .array(let items)? = reply.object?["models"] else { return [] }
        return items.compactMap(\.object).filter { $0["visibility"]?.string == "list" }.compactMap { item in
            item["slug"]?.string.map { AIModelInfo(id: $0, name: item["display_name"]?.string ?? $0, tier: ModelTier(modelID: $0)) }
        }
    }

    static func claudeHTTPError(status: Int, body: Data) -> CloudModelError {
        let message = (try? JSONDecoder().decode(JSONValue.self, from: body))?.object?["error"]?.object?["message"]?.string
        switch status {
        case 401, 403: return .rejected("Claude rejected your API key. Add a new one: voz ai claude -")
        case 429: return .failed("Claude is rate limiting your key. Try again in a minute")
        default: return .failed("Claude failed (\(status))\(message.map { ": \($0)" } ?? "")")
        }
    }

    static func generateWithChatGPT(_ params: GenerateParams) async throws -> String {
        let model = try resolve(params.model, in: try await ModelLists.shared.models(for: .chatgpt))
        let token = try await ChatGPTAccount.shared.accessToken()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(chatGPTBody(params, model: model))
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw chatGPTHTTPError(status: status, body: body)
        }
        return try await chatGPTText(bytes.lines)
    }

    static func chatGPTHTTPError(status: Int, body: Data) -> CloudModelError {
        let reply = (try? JSONDecoder().decode(JSONValue.self, from: body))?.object
        if let code = reply?["error"]?.object?["code"]?.string, code.hasPrefix("subscription_sharing") { return chatGPTError(code: code) }
        switch status {
        case 401: return .rejected("ChatGPT signed you out. Sign in again: voz ai chatgpt")
        case 403: return .rejected("ChatGPT won't serve Voz from here\(reply?["detail"]?.string.map { ": \($0)" } ?? "")")
        default: return .failed("ChatGPT failed (\(status)). Try again")
        }
    }
}

/// Each provider's model list, fetched once an hour. Forgotten when the user picks another account
actor ModelLists {
    static let shared = ModelLists()
    private static let maxAge: TimeInterval = 3600
    private var cached: [AIProvider: (models: [AIModelInfo], at: Date)] = [:]

    func models(for provider: AIProvider) async throws -> [AIModelInfo] {
        if let hit = cached[provider], -hit.at.timeIntervalSinceNow < Self.maxAge { return hit.models }
        let models: [AIModelInfo] = switch provider {
        case .apple: [AIModelInfo(id: "apple", name: "Apple on-device", tier: nil)]
        case .chatgpt: try await CloudModel.chatGPTModels()
        case .claude: try await CloudModel.claudeModels(key: CloudModel.claudeKey())
        }
        cached[provider] = (models, Date())
        return models
    }

    func list(for provider: AIProvider) async throws -> AIModelList {
        AIModelList(provider: provider, models: try await models(for: provider))
    }

    func forget() {
        cached = [:]
    }
}
