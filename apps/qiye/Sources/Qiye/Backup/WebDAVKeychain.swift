import Foundation
import Security

/// Stores the WebDAV password separately from the URL/username, which are not secret.
struct WebDAVKeychain {
    private let service = (Bundle.main.bundleIdentifier ?? "top.mmddskq.qiye") + ".webdav.password"
    private let account = "webdav"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    func read() -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    func save(_ value: String) {
        let values: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let attributes = query.merging(values) { _, new in new }
            _ = SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    func delete() {
        _ = SecItemDelete(query as CFDictionary)
    }
}
