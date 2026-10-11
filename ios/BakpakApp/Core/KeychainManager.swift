import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()
    private init() {}

    private let service = "com.popup.app"
    private let account = "auth.token"
    private let signupTempAccount = "auth.signupTempPassword"

    func saveToken(_ token: String) {
        save(account: account, value: token)
    }

    func readToken() -> String? {
        read(account: account)
    }

    func clearToken() {
        delete(account: account)
    }

    func saveSignupTempPassword(_ password: String) {
        save(account: signupTempAccount, value: password)
    }

    func readSignupTempPassword() -> String? {
        read(account: signupTempAccount)
    }

    func clearSignupTempPassword() {
        delete(account: signupTempAccount)
    }

    private func save(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = query.merging([kSecValueData as String: data]) { _, new in new }
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
