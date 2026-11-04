import CryptoKit
import Foundation
import Network

/// Sign in with ChatGPT, so extensions write with your Plus or Pro plan.
/// Follows developers.openai.com/siwc: a public client with PKCE, a loopback callback and rotating refresh tokens
actor ChatGPTAccount {
    static let shared = ChatGPTAccount()

    struct Credentials: Codable, Sendable {
        let clientID: String
        let email: String
        var idToken: String
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    static let keychainAccount = "chatgpt"
    static let resource = "https://api.openai.com/v1"
    static let issuer = "https://auth.openai.com"
    static let planScope = "chatgpt.tokens.use.direct"
    private static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    private static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    private static let hostIDKey = "chatgptHostID"
    private static let clientIDKey = "chatgptClientID"
    private static let signInWait = Duration.seconds(300)

    private var cached: Credentials?
    private var refreshing: Task<Credentials, any Error>?

    func accessToken() async throws -> String {
        let current = try stored()
        guard current.expiresAt.timeIntervalSinceNow < 300 else { return current.accessToken }
        if let refreshing { return try await refreshing.value.accessToken }
        let task = Task { try await Self.refresh(current) }
        refreshing = task
        defer { refreshing = nil }
        do {
            let renewed = try await task.value
            try save(renewed)
            return renewed.accessToken
        } catch CloudModelError.rejected(let message) {
            try? forget()
            throw CloudModelError.rejected(message)
        }
    }

    /// Opens ChatGPT in your browser and waits until you approve Voz. Returns the account's email
    func signIn(open: @Sendable (URL) async -> Void) async throws -> String {
        let defaults = UserDefaults.standard
        let hostID = defaults.string(forKey: Self.hostIDKey) ?? "urn:uuid:\(UUID().uuidString.lowercased())"
        defaults.set(hostID, forKey: Self.hostIDKey)
        let savedClientID = defaults.string(forKey: Self.clientIDKey)
        let verifier = Self.randomToken()
        let state = Self.randomToken()
        let nonce = Self.randomToken()

        let callback = try await LoopbackCallback.start(path: "/auth/callback", preferredPort: 1455)
        defer { callback.stop() }
        let redirect = "http://127.0.0.1:\(callback.port)/auth/callback"
        var query = [
            ("client_id", savedClientID ?? "dynamic_agent_client"),
            ("ext_agent_host_id", hostID),
            ("response_type", "code"),
            ("redirect_uri", redirect),
            ("scope", "openid profile email offline_access resource.invoke \(Self.planScope)"),
            ("resource", Self.resource),
            ("state", state),
            ("nonce", nonce),
            ("code_challenge_method", "S256"),
            ("code_challenge", Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
        ]
        if savedClientID == nil { query.append(("agent_name_hint", "Voz")) }
        await open(URL(string: "\(Self.authorizeURL.absoluteString)?\(Self.formEncoded(query))")!)

        let reply = try await withTimeout(Self.signInWait, onTimeout: CloudModelError.failed("Sign-in timed out. Run it again when you're ready")) {
            guard let reply = await callback.next() else { throw CancellationError() }
            return reply
        }
        guard reply["state"] == state else { throw CloudModelError.failed("Sign-in came back from a different attempt. Try again") }
        if let error = reply["error"] {
            throw CloudModelError.rejected(error == "access_denied" ? "You didn't allow Voz to use ChatGPT" : "ChatGPT sign-in failed: \(error)")
        }
        guard let code = reply["code"], let clientID = reply["client_id"] ?? savedClientID else {
            throw CloudModelError.failed("ChatGPT didn't finish registering Voz. Try again")
        }
        if let savedClientID, clientID != savedClientID { throw CloudModelError.failed("ChatGPT answered for a different app registration. Try again") }
        defaults.set(clientID, forKey: Self.clientIDKey)

        let tokens = try await Self.post([
            ("grant_type", "authorization_code"),
            ("client_id", clientID),
            ("code", code),
            ("code_verifier", verifier),
            ("redirect_uri", redirect),
            ("resource", Self.resource),
        ])
        let credentials = try Self.credentials(from: tokens, clientID: clientID, nonce: nonce)
        try save(credentials)
        return credentials.email
    }

    /// Ends the session at OpenAI, then forgets the tokens. Returns false when OpenAI couldn't confirm it
    @discardableResult
    func signOut() async -> Bool {
        guard let current = try? stored() else { return true }
        let revoked = await Self.revoke(current)
        try? forget()
        return revoked
    }

    private func stored() throws -> Credentials {
        if let cached { return cached }
        guard let data = try Keychain.read(Self.keychainAccount) else {
            throw CloudModelError.rejected("Sign in to ChatGPT first: voz ai chatgpt")
        }
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        cached = credentials
        return credentials
    }

    private func save(_ credentials: Credentials) throws {
        try Keychain.write(JSONEncoder().encode(credentials), for: Self.keychainAccount)
        cached = credentials
    }

    private func forget() throws {
        cached = nil
        try Keychain.delete(Self.keychainAccount)
    }

    // MARK: Tokens

    private static func refresh(_ current: Credentials) async throws -> Credentials {
        let tokens = try await post([
            ("grant_type", "refresh_token"),
            ("client_id", current.clientID),
            ("refresh_token", current.refreshToken),
            ("resource", resource),
        ])
        guard let access = tokens["access_token"]?.string else { throw CloudModelError.failed("ChatGPT sent no access token") }
        var renewed = current
        renewed.accessToken = access
        renewed.refreshToken = tokens["refresh_token"]?.string ?? current.refreshToken
        renewed.idToken = tokens["id_token"]?.string ?? current.idToken
        renewed.expiresAt = Date(timeIntervalSinceNow: tokens["expires_in"]?.number ?? 3600)
        return renewed
    }

    /// Checks the ID token's claims. Its signature isn't checked: it comes straight from OpenAI's token endpoint over TLS (OpenID Connect Core 3.1.3.7)
    static func credentials(from tokens: [String: JSONValue], clientID: String, nonce: String, now: Date = Date()) throws -> Credentials {
        guard let access = tokens["access_token"]?.string, let refresh = tokens["refresh_token"]?.string, let idToken = tokens["id_token"]?.string else {
            throw CloudModelError.failed("ChatGPT sent an incomplete sign-in. Try again")
        }
        let scopes = (tokens["scope"]?.string ?? "").split(separator: " ")
        guard scopes.contains(Substring(planScope)) else {
            throw CloudModelError.rejected("ChatGPT didn't allow Voz to use your plan. Sign in again and allow it")
        }
        let claims = try idTokenClaims(idToken)
        let audience: [String] = switch claims["aud"] {
        case .string(let value)?: [value]
        case .array(let values)?: values.compactMap(\.string)
        default: []
        }
        guard claims["iss"]?.string == issuer, audience.contains(clientID), claims["nonce"]?.string == nonce,
              let expiry = claims["exp"]?.number, expiry > now.timeIntervalSince1970
        else { throw CloudModelError.failed("ChatGPT's sign-in didn't check out. Try again") }
        return Credentials(
            clientID: clientID,
            email: claims["email"]?.string ?? "ChatGPT",
            idToken: idToken,
            accessToken: access,
            refreshToken: refresh,
            expiresAt: now.addingTimeInterval(tokens["expires_in"]?.number ?? 3600)
        )
    }

    static func idTokenClaims(_ token: String) throws -> [String: JSONValue] {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw CloudModelError.failed("ChatGPT sent a malformed ID token") }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let claims = try? JSONDecoder().decode(JSONValue.self, from: data).object else {
            throw CloudModelError.failed("ChatGPT sent a malformed ID token")
        }
        return claims
    }

    private static func post(_ form: [(String, String)]) async throws -> [String: JSONValue] {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(form).utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let reply = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let code = reply["error"]?.string ?? "unknown"
            let expired = ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"]
            if expired.contains(code) { throw CloudModelError.rejected("Your ChatGPT sign-in expired. Sign in again: voz ai chatgpt") }
            throw CloudModelError.failed("ChatGPT sign-in failed (\(code)). Try again")
        }
        return reply
    }

    private static func revoke(_ credentials: Credentials) async -> Bool {
        do {
            let discovery = try await URLSession.shared.data(from: URL(string: "\(issuer)/.well-known/openid-configuration")!).0
            guard let endpoint = try JSONDecoder().decode(JSONValue.self, from: discovery).object?["revocation_endpoint"]?.string.flatMap(URL.init) else { return false }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(formEncoded([("token", credentials.refreshToken), ("token_type_hint", "refresh_token"), ("client_id", credentials.clientID)]).utf8)
            return (try await URLSession.shared.data(for: request).1 as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: Encoding

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func formEncoded(_ pairs: [(String, String)]) -> String {
        pairs.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: unreserved)!)" }.joined(separator: "&")
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func randomToken() -> String {
        base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }
}

/// Serves http://127.0.0.1:<port><path> until the browser comes back from sign-in
final class LoopbackCallback: Sendable {
    let port: UInt16
    private let listener: NWListener
    private let queries: AsyncStream<[String: String]>
    private let continuation: AsyncStream<[String: String]>.Continuation

    /// Tries the port OpenAI's docs use, then any free one. Only the port may change between sign-ins
    static func start(path: String, preferredPort: UInt16) async throws -> LoopbackCallback {
        do {
            return try await LoopbackCallback(path: path, port: NWEndpoint.Port(rawValue: preferredPort) ?? .any)
        } catch {
            return try await LoopbackCallback(path: path, port: .any)
        }
    }

    private init(path: String, port: NWEndpoint.Port) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        let listener = try NWListener(using: parameters)
        let (queries, continuation) = AsyncStream.makeStream(of: [String: String].self)
        listener.newConnectionHandler = { connection in Self.serve(connection, path: path) { continuation.yield($0) } }
        self.listener = listener
        self.queries = queries
        self.continuation = continuation
        self.port = try await withCheckedThrowingContinuation { ready in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    ready.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error), .waiting(let error):
                    listener.stateUpdateHandler = nil
                    listener.cancel()
                    ready.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    func next() async -> [String: String]? {
        for await query in queries { return query }
        return nil
    }

    func stop() {
        listener.cancel()
        continuation.finish()
    }

    private static let page = """
        <!doctype html><meta charset="utf-8"><title>Voz</title>
        <body style="font: 15px -apple-system, sans-serif; display: grid; place-items: center; height: 90vh; color: #333">
        <p>You're signed in. You can close this tab and go back to Voz.</p>
        """

    private static func serve(_ connection: NWConnection, path: String, deliver: @escaping @Sendable ([String: String]) -> Void) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? ""
            let components = URLComponents(string: "http://127.0.0.1\(target)")
            let matches = components?.path == path
            let body = matches ? page : "Not found"
            let head = "HTTP/1.1 \(matches ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
            guard matches, let items = components?.queryItems else { return }
            deliver(Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first })
        }
    }
}
