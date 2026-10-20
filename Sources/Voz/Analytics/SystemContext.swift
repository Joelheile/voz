import Foundation

enum SystemContext {
    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

    static let properties: [String: String] = [
        "app_version": appVersion,
        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
        "chip": chip,
    ]

    private static var chip: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0 else { return "unknown" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}
