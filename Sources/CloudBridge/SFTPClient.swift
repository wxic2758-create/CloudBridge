import Foundation

enum SFTPClientError: LocalizedError {
    case missingConnectionDetails
    case invalidLocalDirectory
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConnectionDetails:
            "Enter a server address and username."
        case .invalidLocalDirectory:
            "Choose a valid local download folder."
        case .processFailed(let message):
            message.isEmpty ? "The server command failed." : message
        }
    }
}

struct HostKeyIdentity: Identifiable, Equatable, Sendable {
    let keyType: String
    let fingerprint: String
    let knownHostsLine: String

    var id: String { fingerprint }

    var confirmationDescription: String {
        "首次连接到此服务器。请确认主机指纹：\n\(keyType)  \(fingerprint)"
    }
}

enum HostKeyTrustError: LocalizedError {
    case confirmationRequired(HostKeyIdentity)
    case changed(expected: String, actual: HostKeyIdentity)

    var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            return nil
        case let .changed(expected, actual):
            return "服务器主机指纹已变化。已保存：\(expected)；当前：\(actual.fingerprint)。为保护连接，CloudBridge 已阻止此次连接。"
        }
    }
}

actor SFTPClient {
    private enum TransferMode {
        case sftp
        case legacySSH
    }

    private var profile: ServerProfile?
    private var transferMode = TransferMode.sftp
    private let processRunner: any ProcessRunning

    init(processRunner: any ProcessRunning = ProcessRunner()) {
        self.processRunner = processRunner
    }

    func connect(profile: ServerProfile, approvedFingerprint: String? = nil) async throws {
        guard profile.host.isEmpty == false,
              profile.username.isEmpty == false else {
            throw SFTPClientError.missingConnectionDetails
        }

        let hostKey = try await verifyHostKey(for: profile, approvedFingerprint: approvedFingerprint)
        try Self.storeHostKey(hostKey.knownHostsLine)
        self.profile = profile
        transferMode = .sftp
        await startControlConnection(for: profile)
    }

    func disconnect() async throws {
        if let profile {
            await closeControlConnection(for: profile)
        }
        profile = nil
        transferMode = .sftp
    }

    func listDirectory(_ path: String) async throws -> [RemoteItem] {
        switch transferMode {
        case .sftp:
            do {
                let output = try await runSFTPCommands(
                    ["ls -l \(sftpQuote(path))", "bye"],
                    capturesOutput: true
                )
                return parseSFTPDirectoryList(output, currentPath: path)
            } catch {
                guard Self.shouldFallbackToLegacySSH(for: error) else {
                    throw error
                }

                let output = try await runLegacySSH(command: legacyDirectoryListCommand(for: path))
                transferMode = .legacySSH
                return parseDirectoryList(output, currentPath: path)
            }
        case .legacySSH:
            let output = try await runLegacySSH(command: legacyDirectoryListCommand(for: path))
            return parseDirectoryList(output, currentPath: path)
        }
    }

    func download(_ item: RemoteItem, to localDirectory: URL) async throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SFTPClientError.invalidLocalDirectory
        }

        let destination = uniqueDestinationURL(for: item.name, in: localDirectory)

        switch transferMode {
        case .sftp:
            if item.isDirectory {
                try await runSFTPDirectoryDownload(remotePath: item.path, localPath: destination.path)
            } else {
                try await runSFTPFileDownload(remotePath: item.path, localPath: destination.path)
            }
        case .legacySSH:
            try await runLegacySCPDownload(
                remotePath: item.path,
                localPath: destination.path,
                recursively: item.isDirectory
            )
        }

        return destination
    }

    func downloadFileForPreview(_ item: RemoteItem) async throws -> URL {
        let previewDirectory = FileManager.default.temporaryDirectory
            .appending(path: "CloudBridgePreviews", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(
            at: previewDirectory,
            withIntermediateDirectories: true
        )

        let destination = previewDirectory.appending(path: item.name)
        switch transferMode {
        case .sftp:
            try await runSFTPFileDownload(remotePath: item.path, localPath: destination.path)
        case .legacySSH:
            try await runLegacySCPDownload(
                remotePath: item.path,
                localPath: destination.path,
                recursively: false
            )
        }
        return destination
    }

    private func uniqueDestinationURL(for name: String, in directory: URL) -> URL {
        let originalURL = directory.appending(path: name)

        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return originalURL
        }

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = originalURL.pathExtension

        for index in 2...999 {
            let candidateName: String
            if pathExtension.isEmpty {
                candidateName = "\(baseName) \(index)"
            } else {
                candidateName = "\(baseName) \(index).\(pathExtension)"
            }

            let candidateURL = directory.appending(path: candidateName)
            if FileManager.default.fileExists(atPath: candidateURL.path) == false {
                return candidateURL
            }
        }

        return directory.appending(path: "\(baseName) \(UUID().uuidString)")
    }

    private func runSFTPFileDownload(remotePath: String, localPath: String) async throws {
        _ = try await runSFTPCommands(
            ["get -p \(sftpQuote(remotePath)) \(sftpQuote(localPath))", "bye"],
            capturesOutput: false
        )
    }

    private func runSFTPDirectoryDownload(remotePath: String, localPath: String) async throws {
        _ = try await runSFTPCommands(
            ["get -pR \(sftpQuote(remotePath)) \(sftpQuote(localPath))", "bye"],
            capturesOutput: false
        )
    }

    private func runLegacySSH(command: String) async throws -> String {
        guard let profile else {
            throw SFTPClientError.missingConnectionDetails
        }

        if profile.privateKeyPath != nil || profile.password.isEmpty == false {
            return try await runPasswordCommand(
                executable: "/usr/bin/ssh",
                arguments: makeSSHArguments(for: profile, command: command),
                password: profile.password
            )
        }

        return try await runProcess(
            executable: "/usr/bin/ssh",
            arguments: makeSSHArguments(for: profile, command: command)
        )
    }

    private func runLegacySCPDownload(
        remotePath: String,
        localPath: String,
        recursively: Bool
    ) async throws {
        guard let profile else {
            throw SFTPClientError.missingConnectionDetails
        }

        var arguments = makeLegacySCPArguments(for: profile)
        if recursively {
            arguments.append("-r")
        }
        arguments.append("\(profile.username)@\(profile.host):\(remotePath)")
        arguments.append(localPath)

        if profile.password.isEmpty == false {
            _ = try await runPasswordCommand(
                executable: "/usr/bin/scp",
                arguments: arguments,
                password: profile.password,
                capturesOutput: false
            )
        } else {
            _ = try await runProcess(
                executable: "/usr/bin/scp",
                arguments: arguments,
                capturesOutput: false
            )
        }
    }

    private func runSFTPCommands(_ commands: [String], capturesOutput: Bool) async throws -> String {
        guard let profile else {
            throw SFTPClientError.missingConnectionDetails
        }

        let input = Data((commands.joined(separator: "\n") + "\n").utf8)
        // OpenSSH batch mode disables password prompts, including SSH_ASKPASS.
        let arguments = makeSFTPArguments(for: profile, batchMode: profile.password.isEmpty && (profile.privateKeyPath?.isEmpty ?? true))

        if profile.password.isEmpty == false {
            let output = try await runPasswordCommand(
                executable: "/usr/bin/sftp",
                arguments: arguments,
                password: profile.password,
                capturesOutput: capturesOutput,
                standardInputData: input,
                includeStandardErrorInSuccessfulOutput: true
            )
            try Self.throwIfSFTPReportedError(in: output)
            return output
        }

        let output = try await runProcess(
            executable: "/usr/bin/sftp",
            arguments: arguments,
            capturesOutput: capturesOutput,
            standardInputData: input,
            includeStandardErrorInSuccessfulOutput: true
        )
        try Self.throwIfSFTPReportedError(in: output)
        return output
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        capturesOutput: Bool = true,
        standardInputData: Data? = nil,
        environment: [String: String]? = nil,
        includeStandardErrorInSuccessfulOutput: Bool = false,
        timeout: Duration? = nil
    ) async throws -> String {
        do {
            return try await processRunner.run(
                ProcessRequest(
                    executable: executable,
                    arguments: arguments,
                    capturesOutput: capturesOutput,
                    standardInputData: standardInputData,
                    environment: environment,
                    includeStandardErrorInSuccessfulOutput: includeStandardErrorInSuccessfulOutput,
                    currentDirectoryURL: Self.connectionCacheURL(),
                    timeout: timeout
                )
            )
        } catch let error as ProcessRunnerError {
            if case let .failed(message) = error {
                throw SFTPClientError.processFailed(Self.cleanProcessMessage(message))
            }
            throw error
        }
    }

    private func runPasswordCommand(
        executable: String,
        arguments: [String],
        password: String,
        capturesOutput: Bool = true,
        standardInputData: Data? = nil,
        includeStandardErrorInSuccessfulOutput: Bool = false
    ) async throws -> String {
        let environment = try makeAskpassEnvironment(password: password)
        return try await runProcess(
            executable: executable,
            arguments: arguments,
            capturesOutput: capturesOutput,
            standardInputData: standardInputData,
            environment: environment,
            includeStandardErrorInSuccessfulOutput: includeStandardErrorInSuccessfulOutput
        )
    }

    private func makeSFTPArguments(for profile: ServerProfile, batchMode: Bool) -> [String] {
        var arguments = [
            "-q",
            "-P", "\(profile.port)",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(Self.knownHostsPath())",
            "-o", "ConnectTimeout=30",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=60",
            "-o", "ControlPath=\(Self.controlPath())"
        ]

        if let privateKeyPath = profile.privateKeyPath, privateKeyPath.isEmpty == false {
            arguments.append(contentsOf: ["-i", privateKeyPath])
        }

        if profile.password.isEmpty == false {
            if profile.privateKeyPath?.isEmpty ?? true {
                arguments.append(contentsOf: Self.passwordAuthenticationArguments)
            }
            arguments.append(contentsOf: ["-o", "BatchMode=no"])
        } else {
            arguments.append(contentsOf: ["-o", "BatchMode=yes"])
        }

        if batchMode {
            arguments.append(contentsOf: ["-b", "-"])
        }

        arguments.append("\(profile.username)@\(profile.host)")
        return arguments
    }

    private func makeSSHArguments(for profile: ServerProfile, command: String) -> [String] {
        var arguments = connectionArguments(for: profile, portFlag: "-p")
        arguments.append("\(profile.username)@\(profile.host)")
        arguments.append(command)
        return arguments
    }

    private func makeLegacySCPArguments(for profile: ServerProfile) -> [String] {
        ["-O", "-q"] + connectionArguments(for: profile, portFlag: "-P")
    }

    private func connectionArguments(for profile: ServerProfile, portFlag: String) -> [String] {
        var arguments = [
            portFlag, "\(profile.port)",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(Self.knownHostsPath())",
            "-o", "ConnectTimeout=30",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=60",
            "-o", "ControlPath=\(Self.controlPath())"
        ]

        if let privateKeyPath = profile.privateKeyPath, privateKeyPath.isEmpty == false {
            arguments.append(contentsOf: ["-i", privateKeyPath])
        }

        if profile.password.isEmpty == false {
            if profile.privateKeyPath?.isEmpty ?? true {
                arguments.append(contentsOf: Self.passwordAuthenticationArguments)
            }
        } else {
            arguments.append(contentsOf: ["-o", "BatchMode=yes"])
        }

        return arguments
    }

    private func closeControlConnection(for profile: ServerProfile) async {
        _ = try? await runProcess(
            executable: "/usr/bin/ssh",
            arguments: [
                "-o", "ControlPath=\(Self.controlPath())",
                "-O", "exit",
                "-p", "\(profile.port)",
                "\(profile.username)@\(profile.host)"
            ],
            capturesOutput: false
        )
    }

    private func startControlConnection(for profile: ServerProfile) async {
        var arguments = [
            "-M", "-N", "-f",
            "-p", "\(profile.port)",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(Self.knownHostsPath())",
            "-o", "ConnectTimeout=30",
            "-o", "ControlMaster=yes",
            "-o", "ControlPersist=60",
            "-o", "ControlPath=\(Self.controlPath())"
        ]

        if let privateKeyPath = profile.privateKeyPath, privateKeyPath.isEmpty == false {
            arguments.append(contentsOf: ["-i", privateKeyPath])
        }

        if profile.password.isEmpty == false {
            arguments.append(contentsOf: Self.passwordAuthenticationArguments)
            arguments.append(contentsOf: ["-o", "BatchMode=no"])
            _ = try? await runPasswordCommand(
                executable: "/usr/bin/ssh",
                arguments: arguments + ["\(profile.username)@\(profile.host)"],
                password: profile.password,
                capturesOutput: false
            )
        }
        else if profile.privateKeyPath?.isEmpty == false {
            arguments.append(contentsOf: ["-o", "BatchMode=no"])
            _ = try? await runPasswordCommand(
                executable: "/usr/bin/ssh",
                arguments: arguments + ["\(profile.username)@\(profile.host)"],
                password: profile.password,
                capturesOutput: false
            )
        } else {
            arguments.append(contentsOf: ["-o", "BatchMode=yes"])
            _ = try? await runProcess(
                executable: "/usr/bin/ssh",
                arguments: arguments + ["\(profile.username)@\(profile.host)"],
                capturesOutput: false
            )
        }
    }

    private static var passwordAuthenticationArguments: [String] {
        [
            "-o", "PreferredAuthentications=keyboard-interactive,password",
            "-o", "PasswordAuthentication=yes",
            "-o", "KbdInteractiveAuthentication=yes",
            "-o", "PubkeyAuthentication=no",
            "-o", "NumberOfPasswordPrompts=1"
        ]
    }

    private func parseDirectoryList(_ output: String, currentPath: String) -> [RemoteItem] {
        output
            .split(whereSeparator: \.isNewline)
            .map { cleanOutputLine(String($0)) }
            .compactMap { parseFindLine($0, currentPath: currentPath) ?? parseFallbackLine($0, currentPath: currentPath) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func parseSFTPDirectoryList(_ output: String, currentPath: String) -> [RemoteItem] {
        output
            .split(whereSeparator: \.isNewline)
            .map { cleanOutputLine(String($0)) }
            .compactMap { parseSFTPLine($0, currentPath: currentPath) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func cleanProcessMessage(_ message: String) -> String {
        let lines = message
            .replacingOccurrences(of: "\r", with: "")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                line.isEmpty == false &&
                line.hasPrefix("spawn ") == false &&
                line.hasPrefix("LC_ALL=") == false &&
                line.localizedCaseInsensitiveContains("password:") == false &&
                line.contains("ETA") == false
            }

        let joined = lines.joined(separator: "\n")

        if joined.contains("No such file or directory") {
            return "Remote path not found. Go up one level, refresh, or reconnect from the home folder."
        }

        if joined.localizedCaseInsensitiveContains("Permission denied (") ||
           joined.localizedCaseInsensitiveContains("Permission denied, please try again") ||
           joined.localizedCaseInsensitiveContains("authentication failed") {
            return "The server rejected the sign-in. Check the SSH username and password, or confirm that password login is enabled on the server."
        }

        if joined.localizedCaseInsensitiveContains("Permission denied") {
            return "Signed in, but the selected remote path cannot be accessed. Use . for the home folder or choose a permitted path."
        }

        if joined.contains("timed out") || joined.contains("timeout") {
            return "Connection timed out. Check the server IP, port, and network."
        }

        return joined.isEmpty ? "The server command failed." : joined
    }

    private static func throwIfSFTPReportedError(in output: String) throws {
        let errorPrefixes = [
            "ls:",
            "get:",
            "remote readdir",
            "couldn't",
            "connection closed",
            "connection reset",
            "subsystem request failed"
        ]

        let errorLine = output
            .replacingOccurrences(of: "\r", with: "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                let lowercased = line.lowercased()
                return errorPrefixes.contains { lowercased.hasPrefix($0) } ||
                    (lowercased.contains("permission denied") && looksLikeSFTPListing(line) == false) ||
                    (lowercased.contains("no such file or directory") && looksLikeSFTPListing(line) == false)
            }

        if let errorLine {
            throw SFTPClientError.processFailed(cleanProcessMessage(errorLine))
        }
    }

    private static func looksLikeSFTPListing(_ line: String) -> Bool {
        guard line.count > 10,
              let first = line.first,
              "-bcdlps".contains(first) else {
            return false
        }

        let secondIndex = line.index(after: line.startIndex)
        return line[secondIndex] == "r" || line[secondIndex] == "-"
    }

    private func parseFindLine(_ line: String, currentPath: String) -> RemoteItem? {
        let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return nil
        }

        let type = String(parts[0])
        let name = String(parts[3])

        guard isVisibleRemoteName(name) else {
            return nil
        }

        let path = Self.join(currentPath, name)
        return RemoteItem(
            id: path,
            name: name,
            path: path,
            kind: kind(fromFindType: type),
            size: type == "d" ? nil : Int64(parts[1]),
            modifiedAt: Double(parts[2]).map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func parseSFTPLine(_ line: String, currentPath: String) -> RemoteItem? {
        let pattern = "^([bcdlps-])\\S*\\s+.*?\\s+(\\d+)\\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+\\d{1,2}\\s+(?:\\d{2}:\\d{2}|\\d{4})\\s+(.+)$"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
              ),
              let typeRange = Range(match.range(at: 1), in: line),
              let sizeRange = Range(match.range(at: 2), in: line),
              let nameRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        var name = String(line[nameRange])
        if String(line[typeRange]) == "l",
           let targetSeparator = name.range(of: " -> ") {
            name = String(name[..<targetSeparator.lowerBound])
        }
        name = removeListedPathPrefix(from: name, currentPath: currentPath)

        guard isVisibleRemoteName(name) else {
            return nil
        }

        let type = String(line[typeRange])
        let path = Self.join(currentPath, name)
        return RemoteItem(
            id: path,
            name: name,
            path: path,
            kind: kind(fromFindType: type),
            size: type == "d" ? nil : Int64(line[sizeRange]),
            modifiedAt: nil
        )
    }

    private func parseFallbackLine(_ line: String, currentPath: String) -> RemoteItem? {
        guard isVisibleRemoteName(line),
              ignoredOutputPrefixes.contains(where: { line.hasPrefix($0) }) == false else {
            return nil
        }

        let (name, kind) = fallbackNameAndKind(from: line)
        let path = Self.join(currentPath, name)

        return RemoteItem(
            id: path,
            name: name,
            path: path,
            kind: kind,
            size: nil,
            modifiedAt: nil
        )
    }

    private var ignoredOutputPrefixes: [String] {
        [
            "spawn ",
            "Warning:",
            "sftp>",
            "Password:",
            "password:"
        ]
    }

    private func cleanOutputLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isVisibleRemoteName(_ line: String) -> Bool {
        line.isEmpty == false && line != "." && line != ".."
    }

    private func kind(fromFindType type: String) -> RemoteItem.Kind {
        switch type {
        case "d":
            .directory
        case "f":
            .file
        case "l":
            .symlink
        default:
            .unknown
        }
    }

    private func fallbackNameAndKind(from line: String) -> (String, RemoteItem.Kind) {
        guard let suffix = line.last else {
            return (line, .unknown)
        }

        switch suffix {
        case "/":
            return (String(line.dropLast()), .directory)
        case "@":
            return (String(line.dropLast()), .symlink)
        case "*", "|", "=":
            return (String(line.dropLast()), .file)
        default:
            return (line, .file)
        }
    }

    private func removeListedPathPrefix(from name: String, currentPath: String) -> String {
        if name.hasPrefix("./") {
            return String(name.dropFirst(2))
        }

        let prefix = currentPath.hasSuffix("/") ? currentPath : currentPath + "/"
        if currentPath != ".", name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }

        return name
    }

    private func sftpQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func legacyDirectoryListCommand(for path: String) -> String {
        "ls -1FA \(shellQuote(path))"
    }

    private static func shouldFallbackToLegacySSH(for error: any Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("connection closed") ||
            message.contains("subsystem request failed") ||
            message.contains("connection reset")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func knownHostsPath() -> String {
        connectionCacheURL().appending(path: "known_hosts").path
    }

    private func verifyHostKey(
        for profile: ServerProfile,
        approvedFingerprint: String?
    ) async throws -> HostKeyIdentity {
        let output = try await runProcess(
            executable: "/usr/bin/ssh-keyscan",
            arguments: ["-q", "-T", "10", "-p", "\(profile.port)", profile.host],
            timeout: .seconds(15)
        )
        guard let keyLine = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { line in
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                return parts.count >= 3 && line.hasPrefix("#") == false
            }) else {
            throw SFTPClientError.processFailed("无法获取服务器主机指纹。请检查地址、端口和网络连接。")
        }

        let parts = keyLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
        let keyType = String(parts[1])
        let fingerprint = try await fingerprint(for: keyLine)
        let identity = HostKeyIdentity(
            keyType: keyType,
            fingerprint: fingerprint,
            knownHostsLine: keyLine
        )

        if let knownFingerprint = try await knownHostFingerprint(for: profile) {
            guard knownFingerprint == identity.fingerprint else {
                throw HostKeyTrustError.changed(expected: knownFingerprint, actual: identity)
            }
            return identity
        }

        guard approvedFingerprint == identity.fingerprint else {
            throw HostKeyTrustError.confirmationRequired(identity)
        }
        return identity
    }

    private func fingerprint(for knownHostsLine: String) async throws -> String {
        let output = try await runProcess(
            executable: "/usr/bin/ssh-keygen",
            arguments: ["-lf", "-", "-E", "sha256"],
            standardInputData: Data((knownHostsLine + "\n").utf8),
            timeout: .seconds(15)
        )
        guard let fingerprint = output
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first(where: { $0.hasPrefix("SHA256:") }) else {
            throw SFTPClientError.processFailed("无法解析服务器主机指纹。")
        }
        return String(fingerprint)
    }

    private func knownHostFingerprint(for profile: ServerProfile) async throws -> String? {
        let path = Self.knownHostsPath()
        guard let contents = FileManager.default.contents(atPath: path) else {
            return nil
        }

        let endpoint = Self.knownHostsEndpoint(for: profile)
        for line in String(decoding: contents, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.hasPrefix("#") == false else { continue }
            let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3 else { continue }
            let hosts = parts[0].split(separator: ",").map(String.init)
            guard hosts.contains(endpoint) else { continue }
            return try await fingerprint(for: text)
        }
        return nil
    }

    private static func storeHostKey(_ line: String) throws {
        let url = URL(filePath: knownHostsPath())
        let existing = FileManager.default.contents(atPath: url.path) ?? Data()
        let existingText = String(decoding: existing, as: UTF8.self)
        guard existingText.split(whereSeparator: \.isNewline).contains(where: { String($0) == line }) == false else {
            return
        }

        var updated = existingText
        if updated.isEmpty == false, updated.hasSuffix("\n") == false {
            updated.append("\n")
        }
        updated.append(line)
        updated.append("\n")
        try Data(updated.utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func knownHostsEndpoint(for profile: ServerProfile) -> String {
        profile.port == 22 ? profile.host : "[\(profile.host)]:\(profile.port)"
    }

    private static func controlPath() -> String {
        "ssh-%C"
    }

    private static func connectionCacheURL() -> URL {
        let cachesURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )
        .first?
        .appending(path: "CloudBridge", directoryHint: .isDirectory)
        ?? FileManager.default.temporaryDirectory.appending(path: "CloudBridge", directoryHint: .isDirectory)

        try? FileManager.default.createDirectory(
            at: cachesURL,
            withIntermediateDirectories: true
        )

        return cachesURL
    }

    private func makeAskpassEnvironment(password: String) throws -> [String: String] {
        let helperURL = try Self.ensureAskpassHelper()
        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = helperURL.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = "CloudBridge"
        environment["CLOUDBRIDGE_PASSWORD"] = password
        return environment
    }

    private static func ensureAskpassHelper() throws -> URL {
        guard let helperURL = Bundle.main.url(
            forResource: "ssh-askpass",
            withExtension: "sh"
        ) else {
            throw SFTPClientError.processFailed("CloudBridge's sign-in helper is unavailable.")
        }

        return helperURL
    }

    private static func join(_ directory: String, _ name: String) -> String {
        if name == ".." {
            return ".."
        }
        if directory == "." || directory.isEmpty {
            return name
        }
        if directory == "/" {
            return "/" + name
        }
        if directory.hasSuffix("/") {
            return directory + name
        }
        return directory + "/" + name
    }
}
