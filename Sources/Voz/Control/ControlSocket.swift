import AppKit

/// One request per connection: the terminal sends its words, MCP sends a command name and JSON arguments
struct ControlRequest: Codable, Sendable {
    var version: Int? = ControlProtocol.version
    var words: [String]?
    var json: Bool?
    var call: String?
    var arguments: [String: JSONValue]?
}

struct ControlResponse: Codable, Sendable {
    var reply: ControlReply?
    var result: JSONValue?
    var error: ControlError?
}

/// A Unix socket only your user can open, in Voz's Application Support folder
enum ControlSocket {
    static var path: String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/\(AppStorage.folderName)/control.sock").path
    }

    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    static func readLine(_ socket: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while !data.contains(UInt8(ascii: "\n")) {
            let count = read(socket, &buffer, buffer.count)
            guard count > 0 else { return data.isEmpty ? nil : data }
            data.append(buffer, count: count)
        }
        return data.prefix { $0 != UInt8(ascii: "\n") }
    }

    static func writeLine(_ data: Data, to socket: Int32) {
        let line = data + Data("\n".utf8)
        line.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(socket, bytes.baseAddress! + offset, bytes.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }
}

/// Serves the control socket inside the app
final class ControlServer: @unchecked Sendable {
    private let center: ControlCenter
    private let path: String
    private var source: DispatchSourceRead?

    @MainActor
    init(center: ControlCenter, path: String = ControlSocket.path) {
        self.center = center
        self.path = path
    }

    func start() throws {
        unlink(path)
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0, var address = ControlSocket.address(path) else { throw ControlError.failed("Could not create \(path)") }
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, chmod(path, 0o600) == 0, listen(listener, 16) == 0 else {
            close(listener)
            throw ControlError.failed("Could not listen on \(path): \(String(cString: strerror(errno)))")
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .global())
        source.setEventHandler { [weak self] in
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            Thread.detachNewThread { self?.serve(client) }
        }
        source.setCancelHandler { close(listener) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        unlink(path)
    }

    private func serve(_ client: Int32) {
        guard let line = ControlSocket.readLine(client), let request = try? JSONDecoder().decode(ControlRequest.self, from: line) else {
            reply(ControlResponse(error: .usage("Send one JSON request per line")), to: client)
            close(client)
            return
        }
        Task { [center] in
            reply(await Self.respond(to: request, center: center), to: client)
            close(client)
        }
    }

    @MainActor
    static func respond(to request: ControlRequest, center: ControlCenter) async -> ControlResponse {
        if let version = request.version, version != ControlProtocol.version {
            let mismatch = ControlError(code: .versionMismatch, error: "This voz command and the running Voz app are different versions. Quit Voz, then run voz start.")
            return request.words == nil ? ControlResponse(error: mismatch) : ControlResponse(reply: ControlReply(stderr: mismatch.error + "\n", exit: mismatch.exitCode))
        }
        if let words = request.words { return ControlResponse(reply: await center.handle(words, json: request.json ?? false)) }
        guard let name = request.call else { return ControlResponse(error: .usage("Send words or call")) }
        do {
            return ControlResponse(result: try await center.call(name, arguments: request.arguments ?? [:]))
        } catch {
            return ControlResponse(error: ControlCenter.failure(error))
        }
    }

    private func reply(_ response: ControlResponse, to client: Int32) {
        guard let data = try? JSONEncoder.control.encode(response) else { return }
        ControlSocket.writeLine(data, to: client)
    }
}

/// The terminal side: sends one request to the running app. It never opens Voz on its own, so a script can't start the microphone app by surprise
enum ControlClient {
    private static let launchWait = Duration.seconds(15)

    static func send(_ request: ControlRequest, path: String = ControlSocket.path) throws -> ControlResponse {
        guard let socket = try connect(path) else { throw unreachable }
        defer { close(socket) }
        ControlSocket.writeLine(try JSONEncoder.control.encode(request), to: socket)
        guard let line = ControlSocket.readLine(socket) else { throw unreachable }
        return try JSONDecoder().decode(ControlResponse.self, from: line)
    }

    private static var unreachable: ControlError {
        ControlError(code: .unreachable, error: "Voz is not running. Run voz start, then try again.")
    }

    private static func connect(_ path: String) throws -> Int32? {
        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        guard client >= 0, var address = ControlSocket.address(path) else { throw unreachable }
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard connected == 0 else {
            close(client)
            return nil
        }
        return client
    }

    /// `voz start`: opens Voz in the background and waits until it answers. Returns false when it was already running
    static func start(path: String = ControlSocket.path) throws -> Bool {
        if let socket = try connect(path) {
            close(socket)
            return false
        }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", appBundle.path]
        try open.run()
        let deadline = ContinuousClock.now + launchWait
        while ContinuousClock.now < deadline {
            if let socket = try connect(path) {
                close(socket)
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw ControlError(code: .unreachable, error: "Voz did not answer within \(launchWait.components.seconds) seconds. Open voz.app and check that it shows in the menu bar.")
    }

    /// The app this binary belongs to, also when you run it through the `/usr/local/bin/voz` link
    private static var appBundle: URL {
        var url = Bundle.main.executableURL?.resolvingSymlinksInPath() ?? URL(fileURLWithPath: "/")
        while url.path != "/" {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "/Applications/voz.app")
    }
}
