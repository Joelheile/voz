import Foundation

enum SystemAudioAccess {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture"

    static func preflight() -> Int? {
        guard let symbol = symbol("TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: Preflight.self)(service as CFString, nil)
    }

    static func request() async -> Bool {
        guard let symbol = symbol("TCCAccessRequest") else { return false }
        let request = unsafeBitCast(symbol, to: Request.self)
        return await withCheckedContinuation { continuation in
            request(service as CFString, nil) { continuation.resume(returning: $0) }
        }
    }

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
        guard let symbol = dlsym(framework, name) else {
            Log.app.error("\(name, privacy: .public) unavailable")
            return nil
        }
        return symbol
    }
}
