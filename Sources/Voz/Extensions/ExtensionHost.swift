import Foundation

enum ExtensionHostError: Error, Equatable {
    case notReady
    case exitedBeforeReady(Int32)
    case startTimedOut
}

actor ExtensionHost {
    struct Launch: Sendable {
        let bun: URL
        let script: URL
        let home: VozHome
        let packageDirectories: [URL]
    }

    private let launch: Launch
    private let onAction: @Sendable (HostAction) -> Void
    private let onLog: @Sendable (String) -> Void
    private let onExit: @Sendable (Int32) -> Void
    private let generate: @Sendable (GenerateParams) async throws -> String
    private let transcribeFile: @Sendable (TranscribeFileParams) async throws -> FileTranscript
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private let writes = DispatchQueue(label: "com.joelheile.voz.extension-input")
    private var queuedBytes = 0
    private var pending: [Int: CheckedContinuation<Data?, Never>] = [:]
    private var readyWaiter: CheckedContinuation<HostManifest, any Error>?
    private(set) var manifest: HostManifest?

    init(
        launch: Launch,
        onAction: @escaping @Sendable (HostAction) -> Void,
        onLog: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void,
        generate: @escaping @Sendable (GenerateParams) async throws -> String = ExtensionModel.generate,
        transcribeFile: @escaping @Sendable (TranscribeFileParams) async throws -> FileTranscript = { _ in throw FileTranscriberError.needsParakeet }
    ) {
        self.launch = launch
        self.onAction = onAction
        self.onLog = onLog
        self.onExit = onExit
        self.generate = generate
        self.transcribeFile = transcribeFile
    }

    func start(timeout: Duration = .seconds(30)) async throws -> HostManifest {
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        process.executableURL = launch.bun
        process.arguments = ["--no-install", launch.script.path, try launchArguments()]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { await self?.exited(status) }
        }
        let output = Self.lines(from: stdout.fileHandleForReading)
        let errors = Self.lines(from: stderr.fileHandleForReading)
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
        Task { [weak self] in for await chunk in output { await self?.receive(chunk) } }
        Task { [onLog] in for await chunk in errors { onLog(String(decoding: chunk, as: UTF8.self)) } }
        return try await withCheckedThrowingContinuation { continuation in
            readyWaiter = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.startTimedOut()
            }
        }
    }

    func beforeInsert(text: String, raw: String, app: HostApp, timeout: Duration) async -> String {
        guard manifest?.subscribes(to: .beforeInsert) == true else { return text }
        let data = await request("beforeInsert", InsertParams(text: text, raw: raw, app: app), timeout: timeout)
        return decodeResult(TextResult.self, from: data)?.text ?? text
    }

    func transcribe(model: String, path: String, seconds: Double, app: HostApp, timeout: Duration) async -> String? {
        let data = await request("transcribe", TranscribeParams(model: model, path: path, seconds: seconds, app: app), timeout: timeout)
        return decodeResult(TextResult.self, from: data)?.text
    }

    func clean(model: String, text: String, prompt: String, app: HostApp, timeout: Duration) async -> String? {
        let data = await request("clean", CleanParams(model: model, text: text, prompt: prompt, app: app), timeout: timeout)
        return decodeResult(TextResult.self, from: data)?.text
    }

    func cleanupStep(_ step: String, text: String, app: HostApp, timeout: Duration) async -> String? {
        let data = await request("cleanupStep", StepParams(step: step, text: text, app: app), timeout: timeout)
        return decodeResult(TextResult.self, from: data)?.text
    }

    func beforeCleanup(prompt: String, app: HostApp, timeout: Duration) async -> String {
        guard manifest?.subscribes(to: .beforeCleanup) == true else { return prompt }
        let data = await request("beforeCleanup", CleanupParams(prompt: prompt, app: app), timeout: timeout)
        return decodeResult(PromptParams.self, from: data)?.prompt ?? prompt
    }

    func runCommand(_ command: VoiceCommandMatch, app: HostApp, timeout: Duration) async -> Bool {
        let data = await request("command", CommandParams(phrase: command.phrase, at: command.at, text: command.text, app: app), timeout: timeout)
        return decodeResult(CommandResult.self, from: data)?.handled ?? false
    }

    func runAction(_ id: String, app: HostApp, timeout: Duration) async -> Bool {
        decodeResult(EmptyParams.self, from: await request("action", ActionParams(action: id, app: app), timeout: timeout)) != nil
    }

    func stopActivity(_ id: String, app: HostApp, timeout: Duration) async -> Bool {
        decodeResult(EmptyParams.self, from: await request("stopActivity", StopActivityParams(activity: id, app: app), timeout: timeout)) != nil
    }

    @discardableResult
    func emit(_ event: HostEvent, app: HostApp, timeout: Duration) async -> Bool {
        guard manifest?.subscribes(to: event.hook) == true else { return false }
        let result = decodeResult(EmitResult.self, from: await request("emit", EmitParams(event: event.hook.rawValue, payload: event, app: app), timeout: timeout))
        return result?.failed == false
    }

    func ping(timeout: Duration) async -> Bool {
        decodeResult(EmptyParams.self, from: await request("ping", EmptyParams(), timeout: timeout)) != nil
    }

    func stop() {
        if let process {
            process.terminationHandler = nil
            if process.isRunning { process.terminate() }
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        input = nil
        failAll()
    }

    private func launchArguments() throws -> String {
        let arguments = HostLaunchArguments(
            home: launch.home.root.path,
            settings: launch.home.settings.path,
            extensionsDirectory: launch.home.extensions.path,
            packages: launch.packageDirectories.map(\.path)
        )
        return String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
    }

    private func request<Params: Encodable>(_ method: String, _ params: Params, timeout: Duration) async -> Data? {
        guard timeout > .zero, let input else { return nil }
        let deadline = Date().timeIntervalSince1970 * 1000 + Double(timeout.wholeMilliseconds)
        guard let encoded = try? JSONEncoder().encode(HostRequest(id: nextID + 1, method: method, params: params, deadline: deadline)) else { return nil }
        let line = encoded + Data("\n".utf8)
        guard queuedBytes + line.count <= 8 * 1024 * 1024 else {
            onLog("Extension host input limit exceeded for \(method)")
            return nil
        }
        queuedBytes += line.count
        nextID += 1
        let id = nextID
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            writes.async { [weak self] in
                do {
                    try input.write(contentsOf: line)
                    Task { await self?.wrote(line.count, id: id, error: nil) }
                } catch {
                    let message = error.localizedDescription
                    Task { await self?.wrote(line.count, id: id, error: message) }
                }
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.expire(id, method: method)
            }
        }
    }

    private func wrote(_ count: Int, id: Int, error: String?) {
        queuedBytes -= count
        guard let error else { return }
        onLog("Extension host write failed: \(error)")
        resolve(id, with: nil)
    }

    private func decodeResult<Result: Decodable>(_ type: Result.Type, from data: Data?) -> Result? {
        guard let data else { return nil }
        do {
            let response = try JSONDecoder().decode(HostResponse<Result>.self, from: data)
            if let error = response.error { onLog("Extension error: \(error)") }
            return response.result
        } catch {
            onLog("Extension host sent an invalid response: \(error)")
            return nil
        }
    }

    private func receive(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { handle(Data(line)) }
        }
    }

    private func handle(_ line: Data) {
        guard let envelope = try? JSONDecoder().decode(HostEnvelope.self, from: line) else {
            onLog("Extension host output: \(String(decoding: line, as: UTF8.self))")
            return
        }
        if let id = envelope.id {
            resolve(id, with: line)
            return
        }
        if let requestID = envelope.requestID, pending[requestID] == nil { return }
        switch envelope.method {
        case "ready": ready(line)
        case "insert": decodeNotification(TextParams.self, line).map { onAction(.insert($0.text)) }
        case "press": decodeNotification(PressParams.self, line).map { onAction(.press($0.key)) }
        case "notify": decodeNotification(TextParams.self, line).map { onAction(.notify($0.text)) }
        case "actions": decodeNotification(ActionsParams.self, line).map { onAction(.actions($0.actions)) }
        case "startActivity": decodeNotification(ExtensionActivity.self, line).map { onAction(.startActivity($0)) }
        case "endActivity": decodeNotification(IDParams.self, line).map { onAction(.endActivity($0.id)) }
        case "addHistory": decodeNotification(ExtensionHistoryEntry.self, line).map { onAction(.addHistory($0)) }
        case "log": decodeNotification(TextParams.self, line).map { onLog($0.text) }
        case "generate":
            decodeNotification(GenerateParams.self, line).map { params in
                reply(to: params.call, deadline: params.deadline, as: "generated") { [generate] in try await generate(params) }
            }
        case "transcribeFile":
            decodeNotification(TranscribeFileParams.self, line).map { params in
                reply(to: params.call, deadline: params.deadline, as: "transcribedFile") { [transcribeFile] in
                    String(decoding: try JSONEncoder().encode(try await transcribeFile(params)), as: UTF8.self)
                }
            }
        default: onLog("Extension host sent unknown method \(envelope.method ?? "nil")")
        }
    }

    private func reply(to call: Int, deadline: Double, as method: String, with work: @escaping @Sendable () async throws -> String) {
        Task {
            let reply: CallReply
            do {
                reply = CallReply(call: call, json: try await work(), error: nil)
            } catch {
                reply = CallReply(call: call, json: nil, error: error.localizedDescription)
            }
            post(HostReply(method: method, params: reply, deadline: deadline))
        }
    }

    private func post<Params: Encodable>(_ reply: HostReply<Params>) {
        guard let input else { return }
        let line: Data
        do {
            line = try JSONEncoder().encode(reply) + Data("\n".utf8)
        } catch {
            onLog("Extension host reply failed to encode: \(error)")
            return
        }
        writes.async { [onLog] in
            do {
                try input.write(contentsOf: line)
            } catch {
                onLog("Extension host write failed: \(error.localizedDescription)")
            }
        }
    }

    private func decodeNotification<Params: Decodable>(_ type: Params.Type, _ line: Data) -> Params? {
        do {
            return try JSONDecoder().decode(HostNotification<Params>.self, from: line).params
        } catch {
            onLog("Extension host sent invalid params: \(error)")
            return nil
        }
    }

    private func ready(_ line: Data) {
        guard let manifest = decodeNotification(HostManifest.self, line) else { return }
        self.manifest = manifest
        readyWaiter?.resume(returning: manifest)
        readyWaiter = nil
    }

    private func resolve(_ id: Int, with data: Data?) {
        pending.removeValue(forKey: id)?.resume(returning: data)
    }

    private func expire(_ id: Int, method: String) {
        guard pending[id] != nil else { return }
        onLog("Extension \(method) timed out")
        resolve(id, with: nil)
    }

    private func startTimedOut() {
        guard readyWaiter != nil else { return }
        failReady(.startTimedOut)
        stop()
    }

    private func failReady(_ error: ExtensionHostError) {
        readyWaiter?.resume(throwing: error)
        readyWaiter = nil
    }

    private func failAll() {
        failReady(.notReady)
        for id in pending.keys { resolve(id, with: nil) }
        manifest = nil
    }

    private func exited(_ status: Int32) {
        failReady(.exitedBeforeReady(status))
        process = nil
        input = nil
        failAll()
        onExit(status)
    }

    private static func lines(from handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
    }
}
