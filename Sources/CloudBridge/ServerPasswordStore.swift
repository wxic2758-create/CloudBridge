import Foundation
import Security

protocol ServerPasswordStoring: Sendable {
    func readPassword(serverID: UUID) throws -> String?
    func setPassword(_ password: String, serverID: UUID) throws
    func deletePassword(serverID: UUID) throws
}

enum ServerPasswordStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)

}

struct ServerPasswordStore: ServerPasswordStoring {
    static let service = "com.dazhang.CloudBridge.server-password"

    func readPassword(serverID: UUID) throws -> String? {
        var query = baseQuery(serverID: serverID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ServerPasswordStoreError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func setPassword(_ password: String, serverID: UUID) throws {
        let data = Data(password.utf8)
        let query = baseQuery(serverID: serverID)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ServerPasswordStoreError.unexpectedStatus(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw ServerPasswordStoreError.unexpectedStatus(insertStatus)
        }
    }

    func deletePassword(serverID: UUID) throws {
        let status = SecItemDelete(baseQuery(serverID: serverID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ServerPasswordStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(serverID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: serverID.uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}
