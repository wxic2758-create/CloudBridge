import Foundation
import AppKit
import Observation
import Quartz

enum BrowserModelError: LocalizedError {
    case missingHost
    case missingUsername
    case missingPassword
    case securityScopedAccessRequired(String)

    var errorDescription: String? {
        switch self {
        case .missingHost:
            "Enter the server address."
        case .missingUsername:
            "Enter the SSH username."
        case .missingPassword:
            "Enter the server password."
        case .securityScopedAccessRequired(let path):
            "CloudBridge needs permission for \(path). Choose it again with the in-app picker."
        }
    }
}

@Observable
@MainActor
final class BrowserModel {
    var profile = ServerProfile()
    var savedServers: [SavedServer] = []
    var selectedServerID: SavedServer.ID?
    var editingServer = SavedServer()
    var editingPassword = ""
    var isShowingServerEditor = false
    var localDownloadDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    var currentPath = "."
    var items: [RemoteItem] = []
    var selectedItemID: RemoteItem.ID?
    var isConnected = false
    var isLoading = false
    var isDownloading = false
    var statusMessage = "Not connected"
    var errorMessage: String?
    var pendingHostKey: HostKeyIdentity?
    var downloadState = DownloadState.idle
    var downloadTasks: [DownloadTask] = []

    private let client = SFTPClient()
    private let previewer = QuickLookPreviewer()
    private var activeDownloadTaskID: DownloadTask.ID?
    private var activeDownloadOperation: Task<Void, Never>?
    private var pendingConnectionProfile: ServerProfile?

    init() {
        savedServers = SavedServerStore.load()
        localDownloadDirectory = SecurityScopedBookmarkStore.url(for: .downloadDirectory)
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")

        if let firstServer = savedServers.first {
            selectSavedServer(firstServer.id)
        }
    }

    var selectedItem: RemoteItem? {
        items.first { $0.id == selectedItemID }
    }

    var isBusy: Bool {
        isLoading || isDownloading
    }

    func newServer() {
        guard isConnected == false, isLoading == false else {
            return
        }

        editingServer = SavedServer()
        editingPassword = ""
        isShowingServerEditor = true
    }

    func editSelectedServer() {
        guard let server = selectedServer, isConnected == false else {
            return
        }

        editingServer = server
        editingPassword = ServerCredentialStore.password(for: server.id) ?? ""
        isShowingServerEditor = true
    }

    func saveEditingServer() {
        var server = editingServer
        server.name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        server.host = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        server.username = server.username.trimmingCharacters(in: .whitespacesAndNewlines)
        server.defaultRemotePath = normalizedRemotePath(server.defaultRemotePath)

        if let index = savedServers.firstIndex(where: { $0.id == server.id }) {
            savedServers[index] = server
        } else {
            savedServers.append(server)
        }

        do {
            if editingPassword.isEmpty {
                try ServerCredentialStore.deletePassword(for: server.id)
            } else {
                try ServerCredentialStore.save(editingPassword, for: server.id)
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
            return
        }

        SavedServerStore.save(savedServers)
        selectedServerID = server.id
        profile = server.preparedForConnection(password: ServerCredentialStore.password(for: server.id) ?? "")
        currentPath = server.defaultRemotePath
        items = []
        isShowingServerEditor = false
        statusMessage = "Ready to connect"
    }

    func deleteSelectedServer() {
        guard let selectedServerID, isConnected == false, isBusy == false else {
            return
        }

        savedServers.removeAll { $0.id == selectedServerID }
        do {
            try ServerCredentialStore.deletePassword(for: selectedServerID)
        } catch {
            errorMessage = error.localizedDescription
        }
        SavedServerStore.save(savedServers)
        self.selectedServerID = nil
        profile = ServerProfile()
        currentPath = "."
        items = []
        statusMessage = "Choose or add a server"
    }

    func selectSavedServer(_ id: SavedServer.ID?) {
        guard isConnected == false, isBusy == false else {
            return
        }

        selectedServerID = id
        guard let server = selectedServer else {
            profile = ServerProfile()
            currentPath = "."
            items = []
            statusMessage = "Choose or add a server"
            return
        }

        profile = server.preparedForConnection(password: ServerCredentialStore.password(for: server.id) ?? "")
        currentPath = server.defaultRemotePath
        items = []
        selectedItemID = nil
        statusMessage = "Ready to connect"
    }

    var selectedServer: SavedServer? {
        savedServers.first { $0.id == selectedServerID }
    }

    func connect() {
        connect(approvedFingerprint: nil, profile: nil)
    }

    private func connect(approvedFingerprint: String?, profile pendingProfile: ServerProfile?) {
        run { [self] in
            self.statusMessage = "Connecting..."
            let connectionProfile = (pendingProfile ?? self.profile).preparedForConnection()

            if connectionProfile.host.isEmpty {
                throw BrowserModelError.missingHost
            }
            if connectionProfile.username.isEmpty {
                throw BrowserModelError.missingUsername
            }
            if connectionProfile.password.isEmpty {
                throw BrowserModelError.missingPassword
            }

            self.profile = connectionProfile
            do {
                try await self.client.connect(
                    profile: connectionProfile,
                    approvedFingerprint: approvedFingerprint
                )
            } catch let error as HostKeyTrustError {
                switch error {
                case let .confirmationRequired(identity):
                    self.pendingHostKey = identity
                    self.pendingConnectionProfile = connectionProfile
                    self.statusMessage = "等待确认服务器身份"
                    return
                case .changed:
                    throw error
                }
            }
            self.currentPath = self.selectedServer?.defaultRemotePath ?? "."
            try await self.refresh()
            self.isConnected = true
            self.pendingConnectionProfile = nil
            let host = self.profile.host
            self.statusMessage = "\(self.profile.username)@\(host):\(self.profile.port)"
        }
    }

    func approvePendingHostKey() {
        guard let identity = pendingHostKey,
              let pendingConnectionProfile else {
            return
        }

        pendingHostKey = nil
        self.pendingConnectionProfile = nil
        connect(approvedFingerprint: identity.fingerprint, profile: pendingConnectionProfile)
    }

    func rejectPendingHostKey() {
        pendingHostKey = nil
        pendingConnectionProfile = nil
        statusMessage = "未信任服务器主机指纹"
    }

    func disconnect() {
        run { [self] in
            try await self.client.disconnect()
            self.isConnected = false
            self.items = []
            self.selectedItemID = nil
            self.statusMessage = "Disconnected"
        }
    }

    func refresh() async throws {
        var nextItems = try await client.listDirectory(currentPath)
        if currentPath != "." && currentPath != "/" {
            nextItems.insert(.parent, at: 0)
        }
        items = nextItems
        selectedItemID = nil
    }

    func reload() {
        guard isConnected else {
            return
        }

        run { [self] in
            self.statusMessage = "Refreshing..."
            try await self.refresh()
            self.statusMessage = "\(self.profile.username)@\(self.profile.host):\(self.profile.port)"
        }
    }

    func select(_ item: RemoteItem) {
        selectedItemID = item.id
    }

    func open(_ item: RemoteItem) {
        guard item.canTryOpen else {
            selectedItemID = item.id
            return
        }

        run { [self] in
            let previousPath = self.currentPath

            if item.name == ".." {
                self.currentPath = self.parentPath(for: self.currentPath)
            } else {
                self.currentPath = item.path
            }
            self.statusMessage = "Loading \(self.currentPath)..."

            do {
                try await self.refresh()
                self.statusMessage = "\(self.profile.username)@\(self.profile.host):\(self.profile.port)"
            } catch {
                self.currentPath = previousPath
                throw error
            }
        }
    }

    func activate(_ item: RemoteItem) {
        select(item)

        switch item.kind {
        case .directory:
            open(item)
        case .file, .symlink:
            preview(item)
        case .unknown:
            openOrPreview(item)
        }
    }

    func openOrPreview(_ item: RemoteItem) {
        run { [self] in
            let previousPath = self.currentPath
            self.currentPath = item.path
            self.statusMessage = "Opening \(item.name)..."

            do {
                try await self.refresh()
                self.statusMessage = "\(self.profile.username)@\(self.profile.host):\(self.profile.port)"
            } catch {
                self.currentPath = previousPath
                self.statusMessage = "Preparing preview for \(item.name)..."
                let previewURL = try await self.client.downloadFileForPreview(item)
                self.previewer.show(url: previewURL)
                self.statusMessage = "Previewing \(item.name)"
            }
        }
    }

    func preview(_ item: RemoteItem) {
        guard item.name != "..", item.isDirectory == false else {
            return
        }

        run { [self] in
            self.statusMessage = "Preparing preview for \(item.name)..."
            let previewURL = try await self.client.downloadFileForPreview(item)
            self.previewer.show(url: previewURL)
            self.statusMessage = "Previewing \(item.name)"
        }
    }

    func downloadSelected() {
        guard let selectedItem, selectedItem.name != ".." else {
            return
        }

        download(selectedItem)
    }

    func download(_ item: RemoteItem) {
        runDownload { [self] in
            let task = DownloadTask(
                itemName: item.name,
                remotePath: item.path,
                serverName: self.selectedServer?.displayName ?? self.profile.host,
                isDirectory: item.isDirectory
            )
            self.downloadTasks.insert(task, at: 0)
            self.activeDownloadTaskID = task.id
            self.downloadState = .downloading(item.name)
            self.statusMessage = "Downloading \(item.name)..."

            let accessURL = SecurityScopedBookmarkStore.startAccessingURL(
                for: .downloadDirectory,
                matchingPath: self.localDownloadDirectory.path
            )
            if accessURL == nil,
               self.needsExplicitSandboxAccess(for: self.localDownloadDirectory.path) {
                throw BrowserModelError.securityScopedAccessRequired(self.localDownloadDirectory.path)
            }
            defer {
                accessURL?.stopAccessingSecurityScopedResource()
            }

            let destination = try await self.client.download(item, to: self.localDownloadDirectory)
            self.updateTask(task.id, status: .completed, destination: destination)
            self.downloadState = .completed(item.name)
            self.statusMessage = "Downloaded to \(destination.path)"
        }
    }

    func cancelDownload() {
        guard isDownloading else {
            return
        }

        statusMessage = "正在取消下载..."
        activeDownloadOperation?.cancel()
    }

    func retry(_ task: DownloadTask) {
        guard isConnected else {
            statusMessage = "请先连接服务器后再重试下载"
            return
        }

        guard task.serverName == (selectedServer?.displayName ?? profile.host) else {
            statusMessage = "请切换到原服务器后再重试下载"
            return
        }

        let item = RemoteItem(
            id: task.remotePath,
            name: task.itemName,
            path: task.remotePath,
            kind: task.isDirectory ? .directory : .file,
            size: nil,
            modifiedAt: nil
        )
        download(item)
    }

    func chooseLocalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = localDownloadDirectory

        if panel.runModal() == .OK, let url = panel.url {
            localDownloadDirectory = url
            do {
                try SecurityScopedBookmarkStore.save(url, for: .downloadDirectory)
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        }
    }

    func reveal(_ task: DownloadTask) {
        guard let destination = task.destination else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    private func updateTask(_ id: DownloadTask.ID, status: DownloadTask.Status, destination: URL? = nil) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        downloadTasks[index].status = status
        downloadTasks[index].destination = destination
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard isLoading == false else {
            return
        }

        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func runDownload(_ operation: @escaping @MainActor () async throws -> Void) {
        guard isDownloading == false, isLoading == false else {
            return
        }

        isDownloading = true
        errorMessage = nil

        activeDownloadOperation = Task { @MainActor in
            do {
                try await operation()
            } catch let error as ProcessRunnerError where error == .cancelled {
                markActiveDownloadCancelled()
            } catch is CancellationError {
                markActiveDownloadCancelled()
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = error.localizedDescription
                downloadState = .failed(error.localizedDescription)
                if let activeDownloadTaskID {
                    updateTask(activeDownloadTaskID, status: .failed(error.localizedDescription))
                }
            }
            activeDownloadTaskID = nil
            activeDownloadOperation = nil
            isDownloading = false
        }
    }

    private func markActiveDownloadCancelled() {
        if let activeDownloadTaskID {
            updateTask(activeDownloadTaskID, status: .cancelled)
        }
        if case .downloading(let itemName) = downloadState {
            downloadState = .cancelled(itemName)
        }
        statusMessage = "下载已取消"
    }

    private func parentPath(for path: String) -> String {
        let normalizedPath = normalizedRemotePath(path)

        guard normalizedPath != ".", normalizedPath != "/" else {
            return normalizedPath
        }

        if normalizedPath.hasPrefix("/") {
            let parts = normalizedPath.split(separator: "/").map(String.init)

            guard parts.count > 1 else {
                return "/"
            }

            return "/" + parts.dropLast().joined(separator: "/")
        }

        let parts = normalizedPath.split(separator: "/").map(String.init)

        guard parts.count > 1 else {
            return "."
        }

        return parts.dropLast().joined(separator: "/")
    }

    private func normalizedRemotePath(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespacesAndNewlines)

        while path.hasPrefix("./") {
            path.removeFirst(2)
        }

        while path.contains("//") {
            path = path.replacingOccurrences(of: "//", with: "/")
        }

        return path.isEmpty ? "." : path
    }

    private func needsExplicitSandboxAccess(for path: String) -> Bool {
        let standardizedPath = NSString(string: path).standardizingPath
        let downloadsPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Downloads")
            .path

        if standardizedPath == NSString(string: downloadsPath).standardizingPath {
            return false
        }

        return path.hasPrefix("~/.ssh") ||
            path.contains("/.ssh/") ||
            (path.contains("/") == false && path.isEmpty == false) ||
            path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path)
    }
}

private enum SecurityScopedBookmarkKind: String {
    case downloadDirectory = "downloadDirectoryBookmark"
}

private enum SecurityScopedBookmarkStore {
    static func url(for kind: SecurityScopedBookmarkKind) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: kind.rawValue) else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                try save(url, for: kind)
            }

            return url
        } catch {
            UserDefaults.standard.removeObject(forKey: kind.rawValue)
            return nil
        }
    }

    static func startAccessingURL(for kind: SecurityScopedBookmarkKind, matchingPath path: String) -> URL? {
        guard let url = url(for: kind),
              pathsMatch(url.path, path) else {
            return nil
        }

        return url.startAccessingSecurityScopedResource() ? url : nil
    }

    static func save(_ url: URL, for kind: SecurityScopedBookmarkKind) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: kind.rawValue)
    }

    private static func pathsMatch(_ lhs: String, _ rhs: String) -> Bool {
        NSString(string: lhs).standardizingPath == NSString(string: rhs).standardizingPath
    }
}

private final class QuickLookPreviewer: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var previewURL: URL?

    @MainActor
    func show(url: URL) {
        previewURL = url

        guard let panel = QLPreviewPanel.shared() else {
            NSWorkspace.shared.open(url)
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL.map { $0 as NSURL }
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        cleanupPreviewFile()
    }

    private func cleanupPreviewFile() {
        guard let previewURL else {
            return
        }

        let previewDirectory = previewURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: previewDirectory)
        self.previewURL = nil
    }
}
