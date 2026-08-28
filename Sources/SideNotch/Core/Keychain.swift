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

    /// Update-in-place (falling back to add) so a failed save never destroys
    /// the previously stored value. Empty value deletes the item.
    static func write(service: String, value: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        guard !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attrs = query
            attrs[kSecValueData as String] = Data(value.utf8)
            status = SecItemAdd(attrs as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}
