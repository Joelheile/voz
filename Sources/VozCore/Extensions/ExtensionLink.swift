import Foundation

public enum ExtensionLink {
    public static func packageName(in url: URL) -> String? {
        guard url.scheme == "voz", url.host() == "extensions" else { return nil }
        let name = String(url.path().dropFirst()).removingPercentEncoding ?? ""
        guard case .npm(let parsed, let spec)? = try? PackageSource(parsing: "npm:\(name)", relativeTo: URL(fileURLWithPath: "/")), parsed == spec else { return nil }
        return parsed
    }
}
