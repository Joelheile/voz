import Foundation

public enum ExtensionHostError: Error, Equatable {
    case notReady
    case exitedBeforeReady(Int32)
    case startTimedOut
}

public actor ExtensionHost {
    public struct Launch: Sendable {
        public let bun: URL
        public let script: URL
        public let home: VozHome
        public let packageDirectories: [URL]

        public init(bun: URL, script: URL, home: VozHome, packageDirectories: [URL]) {
            self.bun = bun
            self.script = script
            self.home = home
            self.packageDirectories = packageDirectories
        }
    }

    private let launch: Launch
    private let onAction: @Sendable (HostAction) -> Void
    private let onLog: @Sendable (String) -> Void
    private let onExit: @Sendable (Int32) -> Void
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data?, Never>] = [:]
    private var readyWaiter: CheckedContinuation<HostManifest, any Error>?
    public private(set) var manifest: HostManifest?

    public init(
        launch: Launch,
        onAction: @escaping @Sendable (HostAction) -> Void,
        onLog: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) {
        self.launch = launch
        self.onAction = onAction
        self.onLog = onLog
        self.onExit = onExit
    }

    public func start(timeout: Duration = .seconds(10)) async throws -> HostManifest {
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
                await self?.failReady(ExtensionHostError.startTimedOut)
            }
        }
    }

    public func beforeInsert(text: String, raw: String, app: HostApp, timeout: Duration) async -> String {
        guard manifest?.events.contains(HostManifest.beforeInsert) == true else { return text }
        let data = await request("beforeInsert", InsertParams(text: text, raw: raw, app: app), timeout: timeout)
        return decodeResult(InsertResult.self, from: data)?.text ?? text
    }

    public func runCommand(phrase: String, text: String, app: HostApp, timeout: Duration) async -> Bool {
        let data = await request("command", CommandParams(phrase: phrase, text: text, app: app), timeout: timeout)
        return decodeResult(CommandResult.self, from: data)?.handled ?? false
    }

    public func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        input = nil
        failAll()
    }

    private func launchArguments() throws -> String {
        let arguments = HostLaunchArguments(
            settings: launch.home.settings.path,
            extensionsDirectory: launch.home.extensions.path,
            packages: launch.packageDirectories.map(\.path)
        )
        return String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
    }

    private func request<Params: Encodable>(_ method: String, _ params: Params, timeout: Duration) async -> Data? {
        guard let input, let line = try? JSONEncoder().encode(HostRequest(id: nextID + 1, method: method, params: params)) else { return nil }
        nextID += 1
        let id = nextID
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            do {
                try input.write(contentsOf: line + Data("\n".utf8))
            } catch {
                onLog("Extension host write failed: \(error.localizedDescription)")
                resolve(id, with: nil)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.expire(id, method: method)
            }
        }
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
        switch envelope.method {
        case "ready": ready(line)
        case "insert": decodeNotification(TextParams.self, line).map { onAction(.insert($0.text)) }
        case "press": decodeNotification(PressParams.self, line).map { onAction(.press($0.key)) }
        case "log": decodeNotification(TextParams.self, line).map { onLog($0.text) }
        default: onLog("Extension host sent unknown method \(envelope.method ?? "nil")")
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
