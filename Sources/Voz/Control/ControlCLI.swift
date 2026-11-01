import Foundation

/// `voz <command>` in a terminal or an agent's shell. The running app does the work, so both see the same state
enum ControlCLI {
    /// Coding agents set one of these in their shell, so they get JSON without remembering `--json`
    static let agentVariables = ["AI_AGENT", "AGENT", "CLAUDECODE", "CODEX_SANDBOX", "CURSOR_AGENT", "GEMINI_CLI"]

    static func handles(_ arguments: [String]) -> Bool {
        guard arguments.count > 1 else { return false }
        return !arguments[1].hasPrefix("-") || ["--help", "-h"].contains(arguments[1])
    }

    static func wantsJSON(_ words: [String], environment: [String: String]) -> Bool {
        words.contains("--json") || agentVariables.contains { !(environment[$0] ?? "").isEmpty }
    }

    @MainActor
    static func run(_ arguments: [String]) async -> Int32 {
        let all = Array(arguments.dropFirst())
        let json = wantsJSON(all, environment: ProcessInfo.processInfo.environment)
        let words = all.filter { $0 != "--json" }.map { $0 == "-" ? standardInput() : $0 }
        let local = ControlCenter(commands: LocalCommands.all(inTerminal: true))
        let reply: ControlReply
        if LocalCommands.handles(words) {
            reply = await local.handle(words, json: json)
        } else {
            do {
                let response = try ControlClient.send(ControlRequest(words: words, json: json))
                reply = response.reply ?? ControlReply(stderr: (response.error?.error ?? "Voz sent no reply") + "\n", exit: 1)
            } catch let error as ControlError where error.code == .unreachable && ["help", "--help", "-h"].contains(words.first) {
                var offline = await local.handle(words, json: json)
                offline.stderr += "Voz is not running, so its own commands and extension commands are missing. Run voz start to see them.\n"
                reply = offline
            } catch {
                let failure = ControlCenter.failure(error)
                reply = ControlReply(stderr: (json ? failure.json : failure.error) + "\n", exit: failure.exitCode)
            }
        }
        FileHandle.standardOutput.write(Data(reply.stdout.utf8))
        FileHandle.standardError.write(Data(reply.stderr.utf8))
        return reply.exit
    }

    private static func standardInput() -> String {
        String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
