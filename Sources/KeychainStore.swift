import Foundation
import Security

/// Minimal Keychain-backed credential store so the app can remember the /support
/// login and offer to autofill it. Nothing is sent anywhere except decentespresso.com.
enum KeychainStore {
    struct Credentials: Codable {
        var email: String
        var password: String
    }

    private static let account = "support-login"

    static func save(_ creds: Credentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let creds = try? JSONDecoder().decode(Credentials.self, from: data) else {
            return nil
        }
        return creds
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Native API bearer token

    private static let tokenAccount = "api-token"
    // Fallback store used ONLY when the Keychain write actually fails. On an
    // ad-hoc-signed Mac Catalyst dev build (empty entitlements, no keychain-access
    // group) SecItemAdd returns errSecMissingEntitlement and the token silently
    // never persists — so the app forgot the login every launch. A properly signed
    // release build succeeds at the Keychain and never touches this fallback.
    private static let tokenDefaultsKey = "dcamp.api-token.fallback"

    static func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
        } else {
            // Keychain unavailable (e.g. ad-hoc Catalyst) — remember the login anyway.
            UserDefaults.standard.set(token, forKey: tokenDefaultsKey)
        }
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let token = String(data: data, encoding: .utf8), !token.isEmpty {
            return token
        }
        // Keychain miss → the ad-hoc-build fallback (nil if we never stored one).
        let fallback = UserDefaults.standard.string(forKey: tokenDefaultsKey)
        return (fallback?.isEmpty == false) ? fallback : nil
    }

    static func clearToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
    }
}
