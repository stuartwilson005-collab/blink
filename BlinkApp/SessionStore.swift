import Foundation
import Security
import BlinkCore

enum SessionStore {
    private static let service = "BlinkControl.session"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "current"]
    }
    static func load() throws -> Credentials? {
        var query = query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreError.failed(status) }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }
    static func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError.failed(status) }
    }
    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.failed(status) }
    }
    static func client() throws -> BlinkAPI {
        guard let credentials = try load() else { throw BlinkError.signedOut }
        return BlinkAPI(credentials: credentials, persist: { try save($0) })
    }
    enum StoreError: LocalizedError {
        case failed(OSStatus)
        var errorDescription: String? { "Could not access the secure session. Unlock your iPhone and try again." }
    }
}
