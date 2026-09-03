import Foundation
import Security

struct ServerProfile: Codable, Equatable {
    var host = ""
    var port = 22
    var username = ""
    var password = ""

    func preparedForConnection() -> ServerProfile {
        var profile = self
        profile.host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return profile
    }
}

struct SavedServer: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var defaultRemotePath: String

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        defaultRemotePath: String = "."
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.defaultRemotePath = defaultRemotePath
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? host : trimmedName
    }

    var endpoint: String {
        "\(username)@\(host):\(port)"
    }

    func preparedForConnection(password: String) -> ServerProfile {
        ServerProfile(host: host, port: port, username: username, password: password)
            .preparedForConnection()
    }
}

enum SavedServerStore {
    private static let storageKey = "savedServers"

    static func load() -> [SavedServer] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([SavedServer].self, from: data)
        } catch {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return []
        }
    }

    static func save(_ servers: [SavedServer]) {
        guard let data = try? JSONEncoder().encode(servers) else {
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

enum ServerCredentialStore {
    private static let service = "com.dazhang.CloudBridge.server-password"

    static func password(for serverID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ password: String, for serverID: UUID) throws {
        let account = serverID.uuidString
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            try check(SecItemAdd(newItem as CFDictionary, nil))
        } else {
            try check(updateStatus)
        }
    }

    static func deletePassword(for serverID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            try check(status)
            return
        }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Unable to update the saved server password."]
            )
        }
    }
}
