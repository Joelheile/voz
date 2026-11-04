import Foundation
import FoundationModels

final class GenerationSpec: Decodable, Sendable {
    struct Property: Decodable, Sendable {
        let name: String
        let schema: GenerationSpec
        let optional: Bool
    }

    let type: String
    let description: String?
    let choices: [String]?
    let items: GenerationSpec?
    let properties: [Property]?

    init(type: String, description: String? = nil, choices: [String]? = nil, items: GenerationSpec? = nil, properties: [Property]? = nil) {
        self.type = type
        self.description = description
        self.choices = choices
        self.items = items
        self.properties = properties
    }

    private enum CodingKeys: String, CodingKey {
        case type, description, items, properties
        case choices = "enum"
    }
}

struct GenerateParams: Decodable, Sendable {
    let call: Int
    let prompt: String
    let instructions: String?
    let schema: GenerationSpec
    /// A tier such as `balanced`, or an exact model ID. Apple's model ignores it
    let model: String?
    let effort: ModelEffort?
    let deadline: Double
}

enum ExtensionModelError: Error, LocalizedError {
    case unsupportedSchema(String)
    case unavailable(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let type): "Unsupported schema type \"\(type)\""
        case .unavailable(let reason): "The on-device model is unavailable: \(reason)"
        case .timedOut: "The on-device model ran out of time"
        }
    }
}

enum ExtensionModel {
    /// The model name that runs Apple's model whatever the user picked, for background work such as learning
    static let onDevice = "on-device"

    static func generate(_ params: GenerateParams) async throws -> String {
        switch params.model == onDevice ? .apple : AIProvider.current {
        case .apple: try await generateOnDevice(params)
        case .chatgpt: try await cloud(params, name: "ChatGPT", CloudModel.generateWithChatGPT)
        case .claude: try await cloud(params, name: "Claude", CloudModel.generateWithClaude)
        }
    }

    static func models() async throws -> String {
        String(decoding: try JSONEncoder().encode(try await ModelLists.shared.list(for: AIProvider.current)), as: UTF8.self)
    }

    private static func cloud(_ params: GenerateParams, name: String, _ generate: @escaping @Sendable (GenerateParams) async throws -> String) async throws -> String {
        let timeout = Duration.milliseconds(params.deadline - Date().timeIntervalSince1970 * 1000)
        return try await withTimeout(timeout, onTimeout: CloudModelError.failed("\(name) ran out of time")) { try await generate(params) }
    }

    private static func generateOnDevice(_ params: GenerateParams) async throws -> String {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        if case .unavailable(let reason) = model.availability { throw ExtensionModelError.unavailable("\(reason)") }
        let schema = try GenerationSchema(root: dynamicSchema(params.schema, name: "Result"), dependencies: [])
        let session = LanguageModelSession(model: model, instructions: params.instructions)
        let timeout = Duration.milliseconds(params.deadline - Date().timeIntervalSince1970 * 1000)
        return try await withTimeout(timeout, onTimeout: ExtensionModelError.timedOut) {
            try await session.respond(to: params.prompt, schema: schema, options: GenerationOptions(sampling: .greedy)).content.jsonString
        }
    }

    static func dynamicSchema(_ spec: GenerationSpec, name: String) throws -> DynamicGenerationSchema {
        switch spec.type {
        case "string":
            guard let choices = spec.choices else { return DynamicGenerationSchema(type: String.self) }
            return DynamicGenerationSchema(name: name, description: spec.description, anyOf: choices)
        case "number":
            return DynamicGenerationSchema(type: Double.self)
        case "integer":
            return DynamicGenerationSchema(type: Int.self)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        case "array":
            guard let items = spec.items else { throw ExtensionModelError.unsupportedSchema("array without items") }
            return DynamicGenerationSchema(arrayOf: try dynamicSchema(items, name: "\(name)Item"))
        case "object":
            let properties = try (spec.properties ?? []).map { property in
                DynamicGenerationSchema.Property(
                    name: property.name,
                    description: property.schema.description,
                    schema: try dynamicSchema(property.schema, name: "\(name)_\(property.name)"),
                    isOptional: property.optional
                )
            }
            return DynamicGenerationSchema(name: name, description: spec.description, properties: properties)
        default:
            throw ExtensionModelError.unsupportedSchema(spec.type)
        }
    }
}
