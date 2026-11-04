import Foundation
import Security

/// Secrets Voz keeps for you, such as AI sign-ins. The Keychain keeps them from extensions, which run as your user
enum Keychain {
    private static let service = "app.voz.ai"

    static func read(_ account: String) throws -> Data? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query(account).merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 } as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return item as? Data
    }

    static func write(_ data: Data, for account: String) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query(account).merging([kSecValueData: data]) { $1 } as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private static func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}

struct KeychainError: Error, LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "Keychain error: \(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)")"
    }
}
