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
    var password: String
    var defaultRemotePath: String
    var privateKeyPath: String?
    // Authorization metadata only; never contains the private key's contents.
    var privateKeyBookmark: Data?

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, password, defaultRemotePath, privateKeyPath, privateKeyBookmark
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

    func preparedForConnection() -> ServerProfile {
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
    private static let storageKey = "savedServers"

    static func load() -> [SavedServer] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([SavedServer].self, from: data)
        } catch {
            // Preserve the original data for recovery; loading must never delete records.
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
