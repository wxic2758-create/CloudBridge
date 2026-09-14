import Foundation

enum SFTPClientError: LocalizedError {
    case missingConnectionDetails
    case invalidLocalDirectory
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConnectionDetails:
            AppLanguage.text("error.missingConnectionDetails")
        case .invalidLocalDirectory:
            AppLanguage.text("error.invalidLocalDirectory")
        case .processFailed(let message):
            message.isEmpty ? AppLanguage.text("error.serverCommandFailed") : message
        }
    }
}

actor SFTPClient {
    enum DownloadConflictStrategy {
        case rename, replace, skip
    }
    private enum TransferMode {
        case sftp
        case legacySSH
    }

    private var profile: ServerProfile?
    private var transferMode = TransferMode.sftp
    private var directoryCache: [String: [RemoteItem]] = [:]
    private let processRunner: any ProcessRunning

    init(profile: ServerProfile? = nil, processRunner: any ProcessRunning = ProcessRunner()) {
        self.profile = profile
        self.processRunner = processRunner
    }

    func connect(profile: ServerProfile) async throws {
        guard profile.host.isEmpty == false,
              profile.username.isEmpty == false else {
            throw SFTPClientError.missingConnectionDetails
        }

        self.profile = profile
        transferMode = .sftp
        directoryCache.removeAll()
        try await startControlConnection(for: profile)
        try Task.checkCancellation()
    }

    func disconnect() async throws {
        if let profile {
            await closeControlConnection(for: profile)
        }
        profile = nil
        transferMode = .sftp
        directoryCache.removeAll()
    }

    func listDirectory(_ path: String, useCache: Bool = true) async throws -> [RemoteItem] {
        if useCache, let cached = directoryCache[path] {
            return cached
        }

        let items: [RemoteItem]
        switch transferMode {
        case .sftp:
            do {
                let output = try await runSFTPCommands(
                    ["ls -lan \(sftpQuote(path))", "bye"],
                    capturesOutput: true
                )
                items = parseSFTPDirectoryList(output, currentPath: path)
            } catch {
                guard Self.shouldFallbackToLegacySSH(for: error) else {
                    throw error
                }

                let output = try await runLegacySSH(command: legacyDirectoryListCommand(for: path))
                transferMode = .legacySSH
                items = parseDirectoryList(output, currentPath: path)
            }
        case .legacySSH:
            let output = try await runLegacySSH(command: legacyDirectoryListCommand(for: path))
            items = parseDirectoryList(output, currentPath: path)
        }
        directoryCache[path] = items
        return items
    }

    func download(
        _ item: RemoteItem,
        to localDirectory: URL,
        conflictStrategy: DownloadConflictStrategy = .rename,
        progress: (@Sendable (DownloadProgress) async -> Void)? = nil
    ) async throws -> URL {
        try Task.checkCancellation()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SFTPClientError.invalidLocalDirectory
        }
        // Remote names must not escape the chosen directory or inject batch commands.
        guard !item.name.isEmpty, item.name != ".", item.name != "..",
              !item.name.contains("/"), !item.name.contains("\0"),
              !item.path.contains("\n"), !item.path.contains("\r"), !item.path.contains("\0") else {
            throw SFTPClientError.processFailed("The remote filename cannot be downloaded safely.")
        }
        let requested = localDirectory.appending(path: item.localDownloadName)
        if conflictStrategy == .skip, FileManager.default.fileExists(atPath: requested.path) {
            return requested // No progress or transferred bytes for a skipped item.
        }

        // Stage on the same volume. Existing files never contaminate the measured size,
        // concurrent downloads cannot share a target, and failed replacements preserve originals.
        let staging = localDirectory.appending(path: ".cloudbridge-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let stagedFile = staging.appending(path: "payload")
        let mode = transferMode
        let transfer = {
            switch mode {
            case .sftp:
                if item.isDirectory {
                    try await self.runSFTPDirectoryDownload(remotePath: item.path, localPath: stagedFile.path)
                } else {
                    try await self.runSFTPFileDownload(remotePath: item.path, localPath: stagedFile.path)
                }
            case .legacySSH:
                try await self.runLegacySCPDownload(remotePath: item.path, localPath: stagedFile.path, recursively: item.isDirectory)
            }
        }
        if item.isDirectory {
            // Directory inode sizes are not transferred contents. No recursive scans or fake total.
            try await transfer()
        } else {
            try await DownloadProgressSampler.monitor(file: stagedFile,
                totalBytes: item.kind == .file ? item.size : nil, progress: progress, operation: transfer)
        }
        try Task.checkCancellation()
        let destination = conflictStrategy == .rename ? uniqueDestinationURL(for: item.localDownloadName, in: localDirectory) : requested
        if FileManager.default.fileExists(atPath: destination.path) {
            if conflictStrategy == .skip { return destination }
            if conflictStrategy == .replace {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: stagedFile)
                return destination
            }
        }
        try FileManager.default.moveItem(at: stagedFile, to: destination)
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

        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: previewDirectory) } }
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
        try Task.checkCancellation()
        completed = true
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
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(Self.knownHostsPath())",
            "-o", "ConnectTimeout=30",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=600",
            "-o", "ControlPath=\(Self.controlPath())"
        ]

        if let privateKeyPath = profile.privateKeyPath, privateKeyPath.isEmpty == false {
            arguments.append(contentsOf: ["-i", privateKeyPath,
                                          "-o", "IdentitiesOnly=yes",
                                          "-o", "PreferredAuthentications=publickey",
                                          "-o", "PasswordAuthentication=no",
                                          "-o", "KbdInteractiveAuthentication=no"])
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
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(Self.knownHostsPath())",
            "-o", "ConnectTimeout=30",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=600",
            "-o", "ControlPath=\(Self.controlPath())"
        ]

        if let privateKeyPath = profile.privateKeyPath, privateKeyPath.isEmpty == false {
            arguments.append(contentsOf: ["-i", privateKeyPath,
                                          "-o", "IdentitiesOnly=yes",
                                          "-o", "PreferredAuthentications=publickey",
                                          "-o", "PasswordAuthentication=no",
                                          "-o", "KbdInteractiveAuthentication=no"])
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
            capturesOutput: false,
            timeout: .seconds(10)
        )
    }

    func startControlConnection(for profile: ServerProfile) async throws {
        var arguments = [
            "-M", "-N", "-f",
            "-p", "\(profile.port)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(Self.knownHostsPath())",
            "-o", "ConnectTimeout=30",
            "-o", "ControlMaster=yes",
            "-o", "ControlPersist=600",
            "-o", "ControlPath=\(Self.controlPath())"
        ]

        if let privateKeyPath = profile.privateKeyPath, privateKeyPath.isEmpty == false {
            arguments.append(contentsOf: ["-i", privateKeyPath,
                                          "-o", "IdentitiesOnly=yes",
                                          "-o", "PreferredAuthentications=publickey",
                                          "-o", "PasswordAuthentication=no",
                                          "-o", "KbdInteractiveAuthentication=no"])
        }

        if profile.password.isEmpty == false {
            if profile.privateKeyPath?.isEmpty ?? true {
                arguments.append(contentsOf: Self.passwordAuthenticationArguments)
            }
            arguments.append(contentsOf: ["-o", "BatchMode=no"])
            _ = try await runPasswordCommand(
                executable: "/usr/bin/ssh",
                arguments: arguments + ["\(profile.username)@\(profile.host)"],
                password: profile.password,
                capturesOutput: false
            )
        }
        else if profile.privateKeyPath?.isEmpty == false {
            arguments.append(contentsOf: ["-o", "BatchMode=no"])
            _ = try await runProcess(
                executable: "/usr/bin/ssh",
                arguments: arguments + ["\(profile.username)@\(profile.host)"],
                capturesOutput: false
            )
        } else {
            arguments.append(contentsOf: ["-o", "BatchMode=yes"])
            _ = try await runProcess(
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
            return AppLanguage.text("error.remotePathNotFound")
        }

        if joined.localizedCaseInsensitiveContains("Permission denied (") ||
           joined.localizedCaseInsensitiveContains("Permission denied, please try again") ||
           joined.localizedCaseInsensitiveContains("authentication failed") {
            return AppLanguage.text("error.authenticationRejected")
        }

        if joined.localizedCaseInsensitiveContains("Permission denied") {
            return AppLanguage.text("error.remotePathDenied")
        }

        if joined.contains("timed out") || joined.contains("timeout") {
            return AppLanguage.text("error.connectionTimedOut")
        }

        return joined.isEmpty ? AppLanguage.text("error.serverCommandFailed") : joined
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
        guard let match = Self.sftpListingExpression.firstMatch(
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

    private static let sftpListingExpression = try! NSRegularExpression(
        // Some SFTP servers report an unknown hard-link count as "?". Month names
        // and the link-count field are server-dependent, so only size stays numeric.
        pattern: "^([?bcdlps-])\\S*\\s+\\S+\\s+\\S+\\s+\\S+\\s+(\\d+)\\s+\\S+\\s+\\d{1,2}\\s+\\S+\\s+(.+)$"
    )

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
        case "f", "-":
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

    private static func controlPath() -> String {
        "ssh-%C"
    }

    // Use Application Support, not Caches. Caches may be purged by macOS,
    // which would lose OpenSSH's remembered host keys.
    private static func connectionCacheURL() -> URL {
        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        .first?
        .appending(path: "CloudBridge", directoryHint: .isDirectory)
        ?? (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appending(path: "CloudBridge", directoryHint: .isDirectory)

        try? FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )

        return supportURL
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
            throw SFTPClientError.processFailed(AppLanguage.text("error.signInHelperUnavailable"))
        }

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw SFTPClientError.processFailed(AppLanguage.text("error.signInHelperUnavailable"))
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
