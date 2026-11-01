import Foundation

/// `voz mcp`: an MCP server on stdin and stdout. Every command the running app has becomes a tool
enum ControlMCP {
    static let protocolVersion = "2025-06-18"

    static func run() -> Int32 {
        while let line = Swift.readLine() {
            guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else { continue }
            guard let reply = respond(to: message, send: { try ControlClient.send($0) }) else { continue }
            print(reply.text)
            fflush(stdout)
        }
        return 0
    }

    static func respond(to message: JSONValue, send: (ControlRequest) throws -> ControlResponse) -> JSONValue? {
        guard case .object(let fields) = message, let id = fields["id"], let method = fields["method"]?.string else { return nil }
        let params = fields["params"]?.object ?? [:]
        do {
            return .object(["jsonrpc": "2.0", "id": id, "result": try result(method, params: params, send: send)])
        } catch let error as RPCError {
            return .object(["jsonrpc": "2.0", "id": id, "error": .object(["code": .number(Double(error.code)), "message": .string(error.message)])])
        } catch where method == "tools/call" {
            return .object(["jsonrpc": "2.0", "id": id, "result": failure(ControlCenter.failure(error))])
        } catch {
            return .object(["jsonrpc": "2.0", "id": id, "error": .object(["code": -32603, "message": .string(ControlCenter.failure(error).error)])])
        }
    }

    private struct RPCError: Error {
        let code: Int
        let message: String
    }

    private static func result(_ method: String, params: [String: JSONValue], send: (ControlRequest) throws -> ControlResponse) throws -> JSONValue {
        switch method {
        case "initialize":
            return .object([
                "protocolVersion": params["protocolVersion"] ?? .string(protocolVersion),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object(["name": "voz", "version": .string(SystemContext.appVersion)]),
            ])
        case "ping":
            return .object([:])
        case "tools/list":
            return .object(["tools": .array(try commands(send).map(tool))])
        case "tools/call":
            guard let name = params["name"]?.string else { throw RPCError(code: -32602, message: "tools/call needs a name") }
            guard let command = try commands(send).first(where: { toolName($0) == name }) else { throw RPCError(code: -32602, message: "Unknown tool \(name)") }
            let arguments = params["arguments"]?.object ?? [:]
            let response = try send(ControlRequest(call: command.name, arguments: arguments))
            if let error = response.error { return failure(error) }
            let result = response.result ?? .null
            var reply: [String: JSONValue] = ["content": .array([.object(["type": "text", "text": .string(result.pretty)])])]
            if result.object != nil { reply["structuredContent"] = result }
            return .object(reply)
        default:
            throw RPCError(code: -32601, message: "Voz does not handle \(method)")
        }
    }

    private struct Command: Decodable {
        let name: String
        let summary: String
        let readOnly: Bool
        let inputSchema: JSONValue
    }

    private static func commands(_ send: (ControlRequest) throws -> ControlResponse) throws -> [Command] {
        let response = try send(ControlRequest(call: "commands"))
        if let error = response.error { throw error }
        return try JSONDecoder().decode([Command].self, from: JSONEncoder.control.encode(response.result ?? .array([])))
    }

    /// MCP tool names allow letters, digits, `_`, `-` and `.`, so `voz-jira/create` becomes `voz-jira_create`
    private static func toolName(_ command: Command) -> String {
        command.name.replacingOccurrences(of: "/", with: "_")
    }

    private static func tool(_ command: Command) -> JSONValue {
        .object([
            "name": .string(toolName(command)),
            "description": .string(command.summary),
            "inputSchema": command.inputSchema,
            "annotations": .object(["readOnlyHint": .bool(command.readOnly)]),
        ])
    }

    private static func failure(_ error: ControlError) -> JSONValue {
        .object(["content": .array([.object(["type": "text", "text": .string(error.error)])]), "isError": true])
    }
}
