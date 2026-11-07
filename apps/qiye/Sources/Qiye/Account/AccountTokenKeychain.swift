import Foundation
import Security

/// The token is never stored in UserDefaults, a file, or a synchronizable keychain item.
@MainActor
struct AccountTokenKeychain {
    private let service = (Bundle.main.bundleIdentifier ?? "top.mmddskq.qiye")
        + ".github.personal-token"
    private let account = "skqfly"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    func read() throws -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw StorageError.unavailable
        }
        return token
    }

    func readCredential() throws -> GitHubCredential? {
        guard let value = try read() else { return nil }
        if let data = value.data(using: .utf8), let credential = try? JSONDecoder().decode(GitHubCredential.self, from: data) {
            return credential
        }
        return GitHubCredential(accessToken: value, refreshToken: nil, expiresAt: nil)
    }

    func saveCredential(_ credential: GitHubCredential) throws {
        let data = try JSONEncoder().encode(credential)
        guard let value = String(data: data, encoding: .utf8) else { throw StorageError.unavailable }
        try save(value)
    }

    func save(_ token: String) throws {
        let values: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let attributes = query.merging(values) { _, new in new }
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
                throw StorageError.unavailable
            }
        } else if status != errSecSuccess {
            throw StorageError.unavailable
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError.unavailable
        }
    }

    enum StorageError: Error {
        case unavailable
    }
}
