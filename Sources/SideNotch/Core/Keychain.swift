import Foundation
import Security

/// Minimal generic-password Keychain access.
enum Keychain {
    /// Reads a generic password by service name (any account).
    static func read(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(service: String, value: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return true }
        var attrs = base
        attrs[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }
}
