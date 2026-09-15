import Foundation

struct ServerProfile: Codable, Equatable {
    var host = ""
    var port = 22
    var username = ""
    var password = ""
    var privateKeyPath: String?

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
    // Transient only. The custom Codable implementation decodes legacy values
    // for migration but never writes a password back to UserDefaults.
    var password: String
    var defaultRemotePath: String
    var privateKeyPath: String?
    // Authorization metadata only; never contains the private key's contents.
    var privateKeyBookmark: Data?

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, defaultRemotePath, privateKeyPath, privateKeyBookmark
        case password
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        username = try c.decode(String.self, forKey: .username)
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        defaultRemotePath = try c.decode(String.self, forKey: .defaultRemotePath)
        privateKeyPath = try c.decodeIfPresent(String.self, forKey: .privateKeyPath)
        // A damaged/legacy authorization must not make all saved servers disappear.
        privateKeyBookmark = try? c.decodeIfPresent(Data.self, forKey: .privateKeyBookmark)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(host, forKey: .host)
        try c.encode(port, forKey: .port)
        try c.encode(username, forKey: .username)
        try c.encode(defaultRemotePath, forKey: .defaultRemotePath)
        try c.encodeIfPresent(privateKeyPath, forKey: .privateKeyPath)
        try c.encodeIfPresent(privateKeyBookmark, forKey: .privateKeyBookmark)
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        password: String = "",
        defaultRemotePath: String = ".",
        privateKeyPath: String? = nil,
        privateKeyBookmark: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.defaultRemotePath = defaultRemotePath
        self.privateKeyPath = privateKeyPath
        self.privateKeyBookmark = privateKeyBookmark
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? host : trimmedName
    }

    var endpoint: String {
        "\(username)@\(host):\(port)"
    }

    func preparedForConnection(password: String = "") -> ServerProfile {
        ServerProfile(
            host: host,
            port: port,
            username: username,
            password: password,
            privateKeyPath: privateKeyPath
        )
            .preparedForConnection()
    }
}

// One owner for each successful startAccessing call. BrowserModel retains this
// lease across the trust sheet and the entire connection, including transfers.
final class PrivateKeyAccess {
    let url: URL
    let bookmark: Data

    static func makeBookmark(for url: URL) throws -> Data {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    init(bookmark: Data?, path: String) throws {
        guard let bookmark else {
            // Legacy paths are not authorization: reselect through NSOpenPanel.
            throw BrowserModelError.securityScopedAccessRequired(path)
        }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark,
                              options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else {
                throw BrowserModelError.securityScopedAccessRequired(path)
            }
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
                guard values.isRegularFile == true, values.isReadable == true else {
                    throw BrowserModelError.securityScopedAccessRequired(path)
                }
                self.bookmark = stale ? try Self.makeBookmark(for: url) : bookmark
                self.url = url
            } catch {
                url.stopAccessingSecurityScopedResource()
                throw error
            }
        } catch {
            throw BrowserModelError.securityScopedAccessRequired(path)
        }
    }

    deinit {
        url.stopAccessingSecurityScopedResource()
    }
}

enum SavedServerStore {
    static let storageKey = "savedServers"

    static func load(
        defaults: UserDefaults = .standard,
        credentials: any ServerPasswordStoring = ServerPasswordStore()
    ) -> [SavedServer] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        do {
            var servers = try JSONDecoder().decode([SavedServer].self, from: data)
            let legacyServers = servers.filter { !$0.password.isEmpty }
            guard !legacyServers.isEmpty else { return servers }

            // Keep the original UserDefaults value untouched unless every
            // credential has reached Keychain. A later launch can retry safely.
            do {
                for server in legacyServers {
                    try credentials.setPassword(server.password, serverID: server.id)
                }
                for index in servers.indices { servers[index].password = "" }
                save(servers, defaults: defaults)
            } catch {
                // The in-memory legacy password still permits this session's
                // connection; the persisted value remains available for retry.
            }
            return servers
        } catch {
            // Preserve the original data for recovery; loading must never delete records.
            return []
        }
    }

    static func save(_ servers: [SavedServer], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(servers) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }
}
