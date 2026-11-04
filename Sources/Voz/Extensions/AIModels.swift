import AppKit

/// Switches the model extensions write with. One account at a time: picking another one signs out of the last
@MainActor
enum AIModels {
    /// Returns false when OpenAI couldn't confirm the ChatGPT sign-out
    @discardableResult
    static func useApple(_ settings: AppSettings) async -> Bool {
        let revoked = await forget(settings)
        settings.aiModel = .apple
        settings.aiAccount = ""
        return revoked
    }

    static func signInToChatGPT(_ settings: AppSettings) async throws -> String {
        let email = try await ChatGPTAccount.shared.signIn { url in
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }
        if settings.aiModel == .claude { try? Keychain.delete(CloudModel.claudeKeyAccount) }
        await ModelLists.shared.forget()
        settings.aiModel = .chatgpt
        settings.aiAccount = email
        return email
    }

    static func useClaude(key: String, _ settings: AppSettings) async throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CloudModelError.rejected("Paste a Claude API key from platform.claude.com/settings/keys") }
        _ = try await CloudModel.claudeModels(key: key)
        if settings.aiModel == .chatgpt { await ChatGPTAccount.shared.signOut() }
        try Keychain.write(Data(key.utf8), for: CloudModel.claudeKeyAccount)
        await ModelLists.shared.forget()
        settings.aiModel = .claude
        settings.aiAccount = ""
    }

    static let appleButton = "Use Apple's"
    static let claudeButton = "Use key"
    static let chatGPTButton = "Use ChatGPT"

    /// Shown on the first extension hotkey until you pick a model. ChatGPT and Claude write better replies than Apple's
    static let pickCard = AskParams(
        call: 0,
        deadline: 0,
        title: "Which AI should write for you?",
        fields: [AskField(id: "key", label: "Or paste a Claude API key", type: .text, value: .string(""), options: nil)],
        buttons: [appleButton, claudeButton, chatGPTButton],
        remaining: 0
    )

    /// Applies the answer to `pickCard`. Returns true when the action can run now: after a ChatGPT sign-in
    /// the browser is in front, so you tap again.
    static func pick(_ answer: AskAnswer, _ settings: AppSettings) async throws -> Bool {
        switch answer.button {
        case appleButton:
            await useApple(settings)
            return true
        case claudeButton:
            guard case .string(let key) = answer.values["key"] else { return false }
            try await useClaude(key: key, settings)
            return true
        default:
            _ = try await signInToChatGPT(settings)
            return false
        }
    }

    private static func forget(_ settings: AppSettings) async -> Bool {
        await ModelLists.shared.forget()
        switch settings.aiModel {
        case .apple: return true
        case .chatgpt: return await ChatGPTAccount.shared.signOut()
        case .claude:
            try? Keychain.delete(CloudModel.claudeKeyAccount)
            return true
        }
    }
}
