import Foundation

/// Commands the terminal runs itself, so they work while Voz is closed. The app lists them in help and serves the safe ones over MCP
enum LocalCommands {
    private static let home = VozHome()

    /// In the app, `logs --follow` has no terminal to print to, so it refuses
    static func all(inTerminal: Bool) -> [ControlCommand] {
        [start, logs(inTerminal: inTerminal), guide, install, remove, list, update, new, dev, mcp]
    }

    static func handles(_ words: [String]) -> Bool {
        all(inTerminal: true).contains { $0.name == words.first }
    }

    private static var start: ControlCommand {
        ControlCommand(name: "start", summary: "Open Voz in the background and wait until it answers", input: .object([]), terminalOnly: true) { _ in
            let started = try await Task.detached { try ControlClient.start() }.value
            return .message(started ? "Voz is running." : "Voz is already running.", changed: started)
        }
    }

    private static func logs(inTerminal: Bool) -> ControlCommand {
        ControlCommand(
            name: "logs",
            summary: "Print what Voz and its extensions logged, oldest first",
            input: .object([
                .init(name: "extensions", schema: .boolean("Only lines from extensions"), optional: true),
                .init(name: "since", schema: .string("How far back, such as 30s, 10m, 2h or 1d. 10m unless you say"), optional: true),
                .init(name: "lines", schema: .integer("How many of the newest lines, 50 unless you say"), optional: true),
                .init(name: "follow", schema: .boolean("Keep printing new lines until you press Ctrl-C"), optional: true),
            ]),
            readOnly: true
        ) { arguments in
            var predicate = "subsystem == \"\(Log.subsystem)\""
            if arguments["extensions"] == .bool(true) { predicate += " AND category == \"extensions\"" }
            if arguments["follow"] == .bool(true) {
                guard inTerminal else { throw ControlError.usage("--follow works only in a terminal. Leave it out to get the newest lines.") }
                try await Task.detached { try run("stream", "--style", "compact", "--predicate", predicate) }.value
                return ControlOutput(.null, text: "")
            }
            let since = arguments["since"]?.string ?? "10m"
            guard since.wholeMatch(of: /\d+[smhd]/) != nil else { throw ControlError.usage("--since must be a number and s, m, h or d, such as 10m, not \"\(since)\"") }
            let limit = arguments["lines"].flatMap { if case .number(let n) = $0 { Int(n) } else { nil } } ?? 50
            let output = try await Task.detached { try run("show", "--last", since, "--style", "compact", "--predicate", predicate, capture: true) }.value
            let lines = Array(output.split(separator: "\n").map(String.init).dropFirst().suffix(max(0, limit)))
            return ControlOutput(.array(lines.map(JSONValue.string)), text: lines.isEmpty ? "Voz logged nothing in the last \(since)." : lines.joined(separator: "\n"))
        }
    }

    private static var guide: ControlCommand {
        ControlCommand(name: "guide", summary: "Print the guide to building extensions, written for you and your coding agent", input: .object([]), readOnly: true) { _ in
            guard let text = try? String(contentsOf: ExtensionService.resources.appendingPathComponent("AGENTS.md"), encoding: .utf8) else {
                throw ControlError.failed("Voz could not find its extension guide. Reinstall Voz from voz.tools.")
            }
            return ControlOutput(.string(text), text: text)
        }
    }

    // MARK: Packages

    private static func text(_ name: String, _ description: String) -> GenerationSpec.Property {
        .init(name: name, schema: .string(description), optional: false)
    }

    private static var install: ControlCommand {
        ControlCommand(
            name: "install",
            summary: "Install an extension from npm, git or a folder. Find one with voz search",
            input: .object([text("package", "npm name, git:github.com/owner/repo[@ref], an https URL or a folder")]),
            positionals: ["package"],
            terminalOnly: true
        ) { arguments in
            let source = try await Packages.install(arguments["package"]?.string ?? "")
            return .message("\(Packages.warning)\nInstalled \(source.description).")
        }
    }

    private static var remove: ControlCommand {
        ControlCommand(
            name: "remove",
            summary: "Remove an installed extension",
            input: .object([text("package", "Package name or source, as voz list prints it")]),
            positionals: ["package"],
            terminalOnly: true
        ) { arguments in
            .message("Removed \(try await Packages.remove(arguments["package"]?.string ?? "")).")
        }
    }

    private static var list: ControlCommand {
        ControlCommand(name: "list", summary: "List installed packages and extension files, also while Voz is closed", input: .object([]), readOnly: true) { _ in
            let packages = try home.packageSources()
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: home.extensions.path)) ?? [])
                .filter { !$0.hasPrefix(".") }.sorted().map { "\(home.extensions.path)/\($0)" }
            let all = packages + files
            return ControlOutput(
                .object(["packages": .array(packages.map(JSONValue.string)), "files": .array(files.map(JSONValue.string))]),
                text: all.isEmpty ? "No extensions installed. Find one with voz search." : all.joined(separator: "\n")
            )
        }
    }

    private static var update: ControlCommand {
        ControlCommand(name: "update", summary: "Update every extension that isn't pinned to a version", input: .object([]), terminalOnly: true) { _ in
            let count = try await Packages.updateAll()
            return .message("Updated \(count) package\(count == 1 ? "" : "s").", changed: count > 0)
        }
    }

    private static var new: ControlCommand {
        ControlCommand(
            name: "new",
            summary: "Start an extension in a new folder, with a guide for you and your agent",
            input: .object([text("name", "npm package name, such as voz-jira")]),
            positionals: ["name"],
            terminalOnly: true
        ) { arguments in
            let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let folder = try ExtensionTemplate.create(named: arguments["name"]?.string ?? "", in: here, from: ExtensionService.resources)
            let next = [
                "Created \(folder.path). AGENTS.md there explains how to build it. Next:",
                "  voz dev \(folder.lastPathComponent)",
                "  dictate \"say hello\" in any app",
                "  npm publish when it works",
            ]
            return ControlOutput(.object(["folder": .string(folder.path)]), text: next.joined(separator: "\n"))
        }
    }

    private static var dev: ControlCommand {
        ControlCommand(
            name: "dev",
            summary: "Load an extension from a folder, reload it on save and print its logs until Ctrl-C",
            input: .object([text("folder", "The extension folder, such as . or voz-jira")]),
            positionals: ["folder"],
            terminalOnly: true
        ) { arguments in
            let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let url = URL(fileURLWithPath: arguments["folder"]?.string ?? "", relativeTo: here).standardizedFileURL
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { throw PackagesError.missing(url) }
            guard isFolder.boolValue else { throw PackagesError.notAFolder(url) }
            try VozHome.writeTypes(into: url, from: ExtensionService.resources)
            if !ExtensionTemplate.mapsTypes(in: url) {
                print(#"Add "paths": { "voz": ["./voz.d.ts"] } to compilerOptions in tsconfig.json to get types for "voz"."#)
            }
            try await Task.detached {
                try Packages.develop(url) {
                    print("Loaded \(url.path). Voz reloads it when you save. Press Ctrl-C to stop.")
                    fflush(stdout)
                    signal(SIGINT) { _ in }
                    try run("stream", "--style", "compact", "--predicate", "subsystem == \"\(Log.subsystem)\" AND category == \"extensions\"")
                }
            }.value
            return .message("\nUnloaded \(url.path).")
        }
    }

    private static var mcp: ControlCommand {
        ControlCommand(name: "mcp", summary: "Serve Voz's commands to AI apps over MCP, opening Voz if it is closed", input: .object([]), terminalOnly: true) { _ in
            _ = try? await Task.detached { try ControlClient.start() }.value
            _ = await Task.detached { ControlMCP.run() }.value
            return ControlOutput(.null, text: "")
        }
    }

    /// Runs `/usr/bin/log`. Without `capture`, its output goes straight to the terminal
    @discardableResult
    private static func run(_ arguments: String..., capture: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = arguments
        let pipe = Pipe()
        if capture { process.standardOutput = pipe }
        try process.run()
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
