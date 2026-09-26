import Foundation
import Security
import OSLog

protocol ServerPasswordStoring: Sendable {
    func readPassword(serverID: UUID) throws -> String?
    func setPassword(_ password: String, serverID: UUID) throws
    func deletePassword(serverID: UUID) throws
    func retryFailedRead(serverID: UUID)
}

extension ServerPasswordStoring {
    func retryFailedRead(serverID: UUID) {}
}

// Share successful reads and denied requests across windows and model lifetimes.
// Serialize misses so simultaneous callers cannot trigger duplicate authorization.
final class CachedServerPasswordStore: ServerPasswordStoring, @unchecked Sendable {
    static let shared = CachedServerPasswordStore(store: ServerPasswordStore())
    private let store: any ServerPasswordStoring
    private let lock = NSLock()
    private var passwords: [UUID: Result<String?, any Error>] = [:]

    init(store: any ServerPasswordStoring) { self.store = store }

    func retryFailedRead(serverID: UUID) {
        lock.withLock {
            if case .failure? = passwords[serverID] {
                passwords[serverID] = nil
            }
        }
    }

    func readPassword(serverID: UUID) throws -> String? {
        try lock.withLock {
            if let result = passwords[serverID] { return try result.get() }
            let result = Result { try store.readPassword(serverID: serverID) }
            passwords[serverID] = result
            return try result.get()
        }
    }

    func setPassword(_ password: String, serverID: UUID) throws {
        try lock.withLock {
            try store.setPassword(password, serverID: serverID)
            passwords[serverID] = .success(password)
        }
    }

    func deletePassword(serverID: UUID) throws {
        try lock.withLock {
            try store.deletePassword(serverID: serverID)
            passwords[serverID] = .success(nil)
        }
    }
}

enum ServerPasswordStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)

}

struct ServerPasswordStore: ServerPasswordStoring {
    static let service = "com.dazhang.CloudBridge.server-password"
    private static let logger = Logger(subsystem: "com.dazhang.CloudBridge", category: "CredentialAccess")

    func readPassword(serverID: UUID) throws -> String? {
        var query = baseQuery(serverID: serverID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        Self.logger.notice("Keychain read requested")
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        Self.logger.notice("Keychain read completed: status=\(status)")
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
        Self.logger.notice("Keychain update requested")
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        Self.logger.notice("Keychain update completed: status=\(updateStatus)")
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ServerPasswordStoreError.unexpectedStatus(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        Self.logger.notice("Keychain insert completed: status=\(insertStatus)")
        guard insertStatus == errSecSuccess else {
            throw ServerPasswordStoreError.unexpectedStatus(insertStatus)
        }
    }

    func deletePassword(serverID: UUID) throws {
        let status = SecItemDelete(baseQuery(serverID: serverID) as CFDictionary)
        Self.logger.notice("Keychain delete completed: status=\(status)")
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
