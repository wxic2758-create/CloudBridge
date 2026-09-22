import Foundation
import AppKit
import Observation
import Quartz

enum BrowserModelError: LocalizedError {
    case missingHost
    case missingUsername
    case missingPassword
    case invalidPort
    case securityScopedAccessRequired(String)

    var errorDescription: String? {
        switch self {
        case .missingHost:
            AppLanguage.text("error.missingHost")
        case .missingUsername:
            AppLanguage.text("error.missingUsername")
        case .missingPassword:
            AppLanguage.text("editor.password")
        case .invalidPort:
            AppLanguage.text("error.invalidPort")
        case .securityScopedAccessRequired(let path):
            String(format: AppLanguage.text("error.keyAccess"), path)
        }
    }
}
@Observable
@MainActor
final class BrowserModel {
    enum LocalFileStatus: Equatable {
        case none
        case localCopy
        case current
        case missing
        case remoteUpdated
    }

    private struct QueuedDownload {
        let item: RemoteItem
        let taskID: DownloadTask.ID
    }

    var profile = ServerProfile()
    var savedServers: [SavedServer] = []
    var selectedServerID: SavedServer.ID?
    var editingServer = SavedServer()
    var editingPassword = ""
    var isChangingPassword = false
    var isShowingServerEditor = false
    var localDownloadDirectory: URL?
    var currentPath = "."
    var items: [RemoteItem] = []
    var selectedItemIDs: Set<RemoteItem.ID> = []
    var isConnected = false
    var isLoading = false
    var isDownloading = false
    var statusMessage = AppLanguage.text("status.disconnected")
    var isPreparingPreview = false
    var errorMessage: String?
    var downloadState = DownloadState.idle
    var downloadTasks: [DownloadTask] = []
    var lastEnqueuedDownloadTaskID: DownloadTask.ID?

    private let client = SFTPClient()
    private let credentials: any ServerPasswordStoring
    var previewURL: URL?

    func dismissPreview() {
        guard let url = previewURL else { return }
        previewURL = nil
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func showPreview(_ url: URL) {
        dismissPreview()
        previewURL = url
    }
    private var activeDownloadTaskID: DownloadTask.ID?
    private var activeDownloadOperation: Task<Void, Never>?
    private var activeDownloadControl: ProcessControl?
    private var downloadQueue: [QueuedDownload] = []
    private var privateKeyAccess: PrivateKeyAccess?
    private var activeOperation: Task<Void, Never>?
    private var isDisconnecting = false

    private func clearPendingConnection() {
        privateKeyAccess = nil
    }

    init(
        initialServers: [SavedServer]? = nil,
        initialDownloadTasks: [DownloadTask]? = nil,
        loadStoredDownloadDirectory: Bool = true,
        credentials: any ServerPasswordStoring = ServerPasswordStore()
    ) {
        self.credentials = credentials
        savedServers = initialServers ?? SavedServerStore.load(credentials: credentials)
        downloadTasks = initialDownloadTasks ?? (initialServers == nil ? DownloadHistoryStore.load() : [])
        localDownloadDirectory = loadStoredDownloadDirectory
            ? SecurityScopedBookmarkStore.url(for: .downloadDirectory)
            : nil

        if let firstServer = savedServers.first {
            selectSavedServer(firstServer.id)
        }
    }

    var selectedItemID: RemoteItem.ID? {
        get { selectedItemIDs.count == 1 ? selectedItemIDs.first : nil }
        set { selectedItemIDs = newValue.map { Set([$0]) } ?? [] }
    }

    var selectedItems: [RemoteItem] {
        items.filter { selectedItemIDs.contains($0.id) && $0.name != ".." }
    }

    var selectedItem: RemoteItem? {
        selectedItems.count == 1 ? selectedItems.first : nil
    }

    var activeDownloadCount: Int {
        downloadTasks.reduce(into: 0) { count, task in
            if task.status == .queued || task.status == .downloading || task.status == .paused { count += 1 }
        }
    }

    var hasDownloadHistory: Bool {
        downloadTasks.contains { task in
            switch task.status {
            case .queued, .downloading, .paused: false
            case .completed, .cancelled, .failed: true
            }
        }
    }

    var canQueueDownloads: Bool {
        isConnected && !isLoading && !isDisconnecting
    }

    func completedDownload(for item: RemoteItem) -> DownloadTask? {
        guard let serverID = selectedServer?.id else { return nil }
        return downloadTasks.first {
            $0.status == .completed && $0.serverID == serverID && $0.remotePath == item.path
        }
    }

    func existingLocalDownload(for item: RemoteItem) -> URL? {
        var names = [item.localDownloadName]
        if item.localDownloadName != item.name { names.append(item.name) }
        guard let localDownloadDirectory else { return nil }
        return names.lazy
            .map { localDownloadDirectory.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func localFileStatus(for item: RemoteItem) -> LocalFileStatus {
        let task = completedDownload(for: item)
        let taskDestination = task?.destination.flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        }
        let localURL = taskDestination ?? existingLocalDownload(for: item)
        let localExists = localURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        guard let task else { return localExists ? .localCopy : .none }
        guard localExists else { return .missing }
        switch task.remoteMetadataMatches(item) {
        case true: return .current
        case false: return .remoteUpdated
        case nil: return .localCopy
        }
    }

    var isBusy: Bool {
        isLoading || isDownloading || isDisconnecting
    }

    func newServer() {
        guard !isBusy else {
            return
        }

        if !isConnected { clearPendingConnection() }
        editingServer = SavedServer(
            host: "192.168.1.\(Int.random(in: 2...254))",
            username: "root"
        )
        editingPassword = ""
        isChangingPassword = true
        isShowingServerEditor = true
    }

    func editSelectedServer() {
        guard let server = selectedServer, isConnected == false, isBusy == false, !isDisconnecting else {
            return
        }

        clearPendingConnection()
        editingServer = server
        editingPassword = ""
        isChangingPassword = false
        isShowingServerEditor = true
    }

    func saveEditingServer() {
        // Adding a profile must not replace the live connection or its credentials.
        let addingWhileConnected = isConnected && !savedServers.contains { $0.id == editingServer.id }
        guard (!isConnected || addingWhileConnected), !isBusy else { return }
        var server = editingServer
        server.name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        server.host = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        server.username = server.username.trimmingCharacters(in: .whitespacesAndNewlines)
        server.defaultRemotePath = normalizedRemotePath(server.defaultRemotePath)

        guard (1...65535).contains(server.port) else {
            let message = BrowserModelError.invalidPort.localizedDescription
            errorMessage = message
            statusMessage = message
            return
        }

        let existingServer = savedServers.contains { $0.id == server.id }
        do {
            if !editingPassword.isEmpty {
                try credentials.setPassword(editingPassword, serverID: server.id)
            } else if !existingServer {
                throw BrowserModelError.missingPassword
            }
        } catch {
            let message = AppLanguage.text("credentials.writeFailed")
            errorMessage = message
            statusMessage = message
            return
        }
        server.password = ""

        if let index = savedServers.firstIndex(where: { $0.id == server.id }) {
            savedServers[index] = server
        } else {
            savedServers.append(server)
        }

        SavedServerStore.save(savedServers)
        if !addingWhileConnected {
            selectedServerID = server.id
            profile = server.preparedForConnection()
            currentPath = server.defaultRemotePath
            items = []
            statusMessage = AppLanguage.text("connection.ready")
        }
        isShowingServerEditor = false
        editingPassword = ""
        isChangingPassword = false
    }

    func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                editingServer.privateKeyBookmark = try PrivateKeyAccess.makeBookmark(for: url)
                editingServer.privateKeyPath = url.path
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        }
    }

    func clearPrivateKey() {
        editingServer.privateKeyPath = nil
        editingServer.privateKeyBookmark = nil
    }

    func deleteSelectedServer() {
        guard let selectedServerID, isConnected == false, isBusy == false else {
            return
        }

        clearPendingConnection()
        do {
            try credentials.deletePassword(serverID: selectedServerID)
        } catch {
            let message = AppLanguage.text("credentials.removeFailed")
            errorMessage = message
            statusMessage = message
            return
        }
        savedServers.removeAll { $0.id == selectedServerID }
        SavedServerStore.save(savedServers)
        self.selectedServerID = nil
        profile = ServerProfile()
        currentPath = "."
        items = []
        statusMessage = AppLanguage.text("status.noServer")
    }

    func selectSavedServer(_ id: SavedServer.ID?) {
        guard isConnected == false, isBusy == false else {
            return
        }

        clearPendingConnection()
        selectedServerID = id
        guard let server = selectedServer else {
            profile = ServerProfile()
            currentPath = "."
            items = []
            statusMessage = AppLanguage.text("status.noServer")
            return
        }

        profile = server.preparedForConnection(password: password(for: server))
        currentPath = server.defaultRemotePath
        items = []
        selectedItemID = nil
        statusMessage = AppLanguage.text("connection.ready")
    }

    var selectedServer: SavedServer? {
        savedServers.first { $0.id == selectedServerID }
    }

    func preparedProfileForConnection() -> ServerProfile {
        // The selected saved server is the source of truth. `profile` is transient and
        // intentionally loses its password when a connection is torn down.
        if let selectedServer {
            return selectedServer.preparedForConnection(password: password(for: selectedServer))
        }
        return profile.preparedForConnection()
    }

    func removeEditingPassword() {
        guard savedServers.contains(where: { $0.id == editingServer.id }) else { return }
        do {
            try credentials.deletePassword(serverID: editingServer.id)
            isChangingPassword = true
            editingPassword = ""
        } catch {
            let message = AppLanguage.text("credentials.removeFailed")
            errorMessage = message
            statusMessage = message
        }
    }

    func hasSavedPassword(for server: SavedServer) -> Bool {
        (try? credentials.readPassword(serverID: server.id))?.isEmpty == false
    }

    private func password(for server: SavedServer) -> String {
        (try? credentials.readPassword(serverID: server.id)) ?? server.password
    }

    func connect() {
        guard !isConnected, !isBusy else { return }
        clearPendingConnection()
        run { [self] in
            self.statusMessage = AppLanguage.text("status.connecting")
            var connectionProfile = self.preparedProfileForConnection()

            if connectionProfile.host.isEmpty {
                throw BrowserModelError.missingHost
            }
            if connectionProfile.username.isEmpty {
                throw BrowserModelError.missingUsername
            }
            if (1...65535).contains(connectionProfile.port) == false {
                throw BrowserModelError.invalidPort
            }
            if connectionProfile.password.isEmpty && (connectionProfile.privateKeyPath?.isEmpty ?? true) {
                throw BrowserModelError.missingPassword
            }
            if let key = connectionProfile.privateKeyPath, !key.isEmpty {
                guard let index = savedServers.firstIndex(where: { $0.id == selectedServerID }),
                      savedServers[index].privateKeyPath == key else {
                    throw BrowserModelError.securityScopedAccessRequired(key)
                }
                let access = try PrivateKeyAccess(bookmark: savedServers[index].privateKeyBookmark, path: key)
                privateKeyAccess = access
                // Bookmarks track moves. Refresh stale metadata only while access is active.
                savedServers[index].privateKeyPath = access.url.path
                savedServers[index].privateKeyBookmark = access.bookmark
                SavedServerStore.save(savedServers)
                connectionProfile.privateKeyPath = access.url.path
            }

            self.profile = connectionProfile
            try await self.client.connect(profile: connectionProfile)
            try Task.checkCancellation()
            self.currentPath = self.selectedServer?.defaultRemotePath ?? "."
            try await self.refresh()
            try Task.checkCancellation()
            self.isConnected = true
            let host = self.profile.host
            self.statusMessage = AppLanguage.text("connection.connected") + " — \(self.profile.username)@\(host):\(self.profile.port)"
        }
    }

    func switchServer(to id: SavedServer.ID) {
        guard !isBusy, id != selectedServerID,
              savedServers.contains(where: { $0.id == id }) else { return }
        if isConnected {
            disconnect(nextServerID: id)
        } else {
            selectSavedServer(id)
            connect()
        }
    }

    func disconnect() { disconnect(nextServerID: nil) }

    private func disconnect(nextServerID: SavedServer.ID?) {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        let operation = activeOperation
        let download = activeDownloadOperation
        operation?.cancel()
        download?.cancel()
        Task { @MainActor in
            // Cancellation is a request, not completion. Keep the key authorized until
            // all operations and control-connection cleanup have actually returned.
            await operation?.value
            await download?.value
            finishPendingDownloads(status: .cancelled)
            downloadQueue.removeAll()
            try? await client.disconnect()
            clearPendingConnection()
            isConnected = false
            profile.password = ""
            items = []
            selectedItemID = nil
            statusMessage = AppLanguage.text("status.disconnected")
            isDisconnecting = false
            if let nextServerID {
                selectSavedServer(nextServerID)
                connect()
            }
        }
    }

    func refresh(forceReload: Bool = false) async throws {
        var nextItems = try await client.listDirectory(currentPath, useCache: !forceReload)
        if currentPath != "." && currentPath != "/" {
            nextItems.insert(.parent, at: 0)
        }
        try Task.checkCancellation()
        items = nextItems
        selectedItemID = nil
    }

    func reload() {
        guard isConnected else {
            return
        }

        run { [self] in
            self.statusMessage = AppLanguage.text("status.refreshing")
            try await self.refresh(forceReload: true)
            self.statusMessage = AppLanguage.text("connection.connected") + " — \(self.profile.username)@\(self.profile.host):\(self.profile.port)"
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
            self.statusMessage = String(format: AppLanguage.text("status.loadingPath"), self.currentPath)

            do {
                try await self.refresh()
                self.statusMessage = AppLanguage.text("connection.connected") + " — \(self.profile.username)@\(self.profile.host):\(self.profile.port)"
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
            self.statusMessage = String(format: AppLanguage.text("status.openingItem"), item.name)

            do {
                try await self.refresh()
                self.statusMessage = AppLanguage.text("connection.connected") + " — \(self.profile.username)@\(self.profile.host):\(self.profile.port)"
            } catch {
                try Task.checkCancellation()
                self.currentPath = previousPath
                self.isPreparingPreview = true
                self.statusMessage = String(format: AppLanguage.text("status.preparingPreview"), item.name)
                defer { self.isPreparingPreview = false }
                let previewURL = try await self.client.downloadFileForPreview(item)
                self.showPreview(previewURL)
                self.statusMessage = String(format: AppLanguage.text("status.previewingItem"), item.name)
            }
        }
    }

    func preview(_ item: RemoteItem) {
        guard item.name != "..", item.isDirectory == false else {
            return
        }

        run { [self] in
            self.isPreparingPreview = true
            defer { self.isPreparingPreview = false }
            self.statusMessage = String(format: AppLanguage.text("status.preparingPreview"), item.name)
            let previewURL = try await self.client.downloadFileForPreview(item)
            self.showPreview(previewURL)
            self.statusMessage = String(format: AppLanguage.text("status.previewingItem"), item.name)
        }
    }

    func downloadSelected() {
        download(selectedItems)
    }

    func download(_ item: RemoteItem) {
        download([item])
    }

    func download(_ items: [RemoteItem]) {
        let acceptedItems = items.filter { $0.name != ".." }
        guard canQueueDownloads, !acceptedItems.isEmpty else { return }

        if localDownloadDirectory == nil {
            guard chooseLocalDirectory() else { return }
        }

        enqueueDownloads(acceptedItems)
    }

    private func enqueueDownloads(_ items: [RemoteItem]) {
        guard !items.isEmpty else { return }

        let serverName = selectedServer?.displayName ?? profile.host
        let serverID = selectedServer?.id
        let jobs = items.map { item in
            let task = DownloadTask(
                itemName: item.name,
                remotePath: item.path,
                serverName: serverName,
                isDirectory: item.isDirectory,
                serverID: serverID,
                remoteSize: item.size,
                remoteModifiedAt: item.modifiedAt,
                status: .queued
            )
            return (item: item, task: task)
        }
        downloadTasks.insert(contentsOf: jobs.map(\.task), at: 0)
        downloadQueue.append(contentsOf: jobs.map { QueuedDownload(item: $0.item, taskID: $0.task.id) })
        lastEnqueuedDownloadTaskID = jobs.first?.task.id

        guard !isDownloading else { return }
        runDownloadQueue()
    }

    private func runDownloadQueue() {
        runDownload { [self] in
            guard let localDownloadDirectory = self.localDownloadDirectory else {
                throw BrowserModelError.securityScopedAccessRequired(AppLanguage.text("settings.folderHelp"))
            }
            let accessURL = SecurityScopedBookmarkStore.startAccessingURL(
                for: .downloadDirectory,
                matchingPath: localDownloadDirectory.path
            )
            if accessURL == nil {
                throw BrowserModelError.securityScopedAccessRequired(localDownloadDirectory.path)
            }
            defer {
                accessURL?.stopAccessingSecurityScopedResource()
                self.activeDownloadControl = nil
            }

            while !self.downloadQueue.isEmpty {
                try Task.checkCancellation()
                let job = self.downloadQueue.removeFirst()
                self.activeDownloadTaskID = job.taskID
                let processControl = ProcessControl()
                self.activeDownloadControl = processControl
                self.startTask(job.taskID)
                self.downloadState = .downloading(job.item.name)
                self.statusMessage = String(format: AppLanguage.text("status.downloadingItem"), job.item.name)

                do {
                    let destination = try await self.client.download(
                        job.item,
                        to: localDownloadDirectory,
                        processControl: processControl
                    ) { [weak self, taskID = job.taskID] progress in
                        await MainActor.run {
                            guard let self, self.activeDownloadTaskID == taskID,
                                  self.activeDownloadOperation?.isCancelled == false else { return }
                            self.updateTask(taskID, progress: progress)
                        }
                    }
                    self.updateTask(job.taskID, status: .completed, destination: destination)
                    self.downloadState = .completed(job.item.name)
                    self.statusMessage = String(format: AppLanguage.text("status.downloaded"), destination.path)
                } catch let error as ProcessRunnerError where error == .cancelled {
                    throw error
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    self.updateTask(job.taskID, status: .failed(error.localizedDescription))
                    self.downloadState = .failed(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = error.localizedDescription
                }
                self.activeDownloadControl = nil
            }
        }
    }

    func cancelDownload() {
        guard let activeDownloadTaskID,
              let task = downloadTasks.first(where: { $0.id == activeDownloadTaskID }) else { return }
        cancelDownload(task)
    }

    func cancelDownload(_ task: DownloadTask) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == task.id }) else { return }
        switch downloadTasks[index].status {
        case .queued:
            downloadQueue.removeAll { $0.taskID == task.id }
            downloadTasks[index].finish(status: .cancelled)
            DownloadHistoryStore.save(downloadTasks)
        case .downloading, .paused:
            guard activeDownloadTaskID == task.id else { return }
            statusMessage = AppLanguage.text("status.cancellingDownload")
            activeDownloadOperation?.cancel()
        case .completed, .cancelled, .failed:
            return
        }
    }

    func pauseDownload(_ task: DownloadTask) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == task.id }),
              downloadTasks[index].status == .downloading,
              activeDownloadTaskID == task.id,
              activeDownloadControl?.pause() == true else { return }
        downloadTasks[index].pause()
        downloadState = .paused(task.itemName)
        statusMessage = AppLanguage.text("action.pause")
    }

    func resumeDownload(_ task: DownloadTask) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == task.id }),
              downloadTasks[index].status == .paused,
              activeDownloadTaskID == task.id,
              activeDownloadControl?.resume() == true else { return }
        downloadTasks[index].resume()
        downloadState = .downloading(task.itemName)
        statusMessage = AppLanguage.text("action.resume")
    }

    func canRetry(_ task: DownloadTask) -> Bool {
        guard canQueueDownloads, task.belongs(to: selectedServer?.id) else { return false }
        return switch task.status {
        case .cancelled, .failed: true
        case .queued, .downloading, .paused, .completed: false
        }
    }

    func retry(_ task: DownloadTask) {
        guard isConnected else {
            statusMessage = AppLanguage.text("status.retryConnectFirst")
            return
        }

        guard task.belongs(to: selectedServer?.id) else {
            statusMessage = AppLanguage.text("status.retrySameServer")
            return
        }

        guard canRetry(task) else { return }

        guard let index = downloadTasks.firstIndex(where: { $0.id == task.id }),
              downloadTasks[index].prepareForRetry() else { return }

        let item = RemoteItem(
            id: task.remotePath,
            name: task.itemName,
            path: task.remotePath,
            kind: task.isDirectory ? .directory : .file,
            size: task.remoteSize,
            modifiedAt: task.remoteModifiedAt
        )
        downloadQueue.append(QueuedDownload(item: item, taskID: task.id))
        lastEnqueuedDownloadTaskID = task.id
        DownloadHistoryStore.save(downloadTasks)

        guard !isDownloading else { return }
        runDownloadQueue()
    }

    @discardableResult
    func chooseLocalDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = localDownloadDirectory

        if panel.runModal() == .OK, let url = panel.url {
            localDownloadDirectory = url
            do {
                try SecurityScopedBookmarkStore.save(url, for: .downloadDirectory)
                return true
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = error.localizedDescription
            }
        }
        return false
    }

    func reveal(_ task: DownloadTask) {
        guard let destination = task.destination else { return }
        revealLocalDestination(destination, taskID: task.id)
    }

    func revealDownloaded(_ item: RemoteItem) {
        let task = completedDownload(for: item)
        let taskDestination = task?.destination.flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        }
        guard let destination = taskDestination ?? existingLocalDownload(for: item) else { return }
        revealLocalDestination(destination, taskID: task?.id)
    }

    private func revealLocalDestination(_ originalDestination: URL, taskID: DownloadTask.ID?) {
        var destination = originalDestination

        if destination.lastPathComponent.hasPrefix("."),
           FileManager.default.fileExists(atPath: destination.path) {
            let accessURL = SecurityScopedBookmarkStore.startAccessingURL(
                for: .downloadDirectory,
                matchingPath: localDownloadDirectory?.path ?? destination.deletingLastPathComponent().path
            )
            defer { accessURL?.stopAccessingSecurityScopedResource() }
            do {
                let visibleDestination = availableVisibleDestination(for: destination)
                try FileManager.default.moveItem(at: destination, to: visibleDestination)
                destination = visibleDestination
                if let taskID, let index = downloadTasks.firstIndex(where: { $0.id == taskID }) {
                    downloadTasks[index].destination = destination
                    DownloadHistoryStore.save(downloadTasks)
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    private func availableVisibleDestination(for hiddenURL: URL) -> URL {
        let directory = hiddenURL.deletingLastPathComponent()
        let visibleName = "_\(hiddenURL.lastPathComponent)"
        let preferred = directory.appending(path: visibleName)
        guard FileManager.default.fileExists(atPath: preferred.path) else { return preferred }
        for index in 2...999 {
            let candidate = directory.appending(path: "\(visibleName) \(index)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appending(path: "\(visibleName) \(UUID().uuidString)")
    }

    /// Removes finished records while preserving queued and active transfers.
    func clearDownloadHistory() {
        downloadTasks.removeAll { task in
            switch task.status {
            case .queued, .downloading, .paused: false
            case .completed, .cancelled, .failed: true
            }
        }
        DownloadHistoryStore.save(downloadTasks)
    }

    func removeDownloadRecord(_ task: DownloadTask) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == task.id }) else { return }
        switch downloadTasks[index].status {
        case .completed, .cancelled, .failed:
            downloadTasks.remove(at: index)
            DownloadHistoryStore.save(downloadTasks)
        case .queued, .downloading, .paused:
            return
        }
    }

    private func updateTask(_ id: DownloadTask.ID, progress: DownloadProgress) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == id }) else { return }
        downloadTasks[index].apply(progress)
    }

    private func startTask(_ id: DownloadTask.ID) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == id }) else { return }
        downloadTasks[index].start()
    }

    private func updateTask(_ id: DownloadTask.ID, status: DownloadTask.Status, destination: URL? = nil) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        downloadTasks[index].finish(status: status, destination: destination)
        DownloadHistoryStore.save(downloadTasks)
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else {
            return
        }

        isLoading = true
        errorMessage = nil

        activeOperation = Task { @MainActor in
            do {
                try Task.checkCancellation()
                try await operation()
            } catch {
                if !isConnected {
                    // Use an uncancelled task for cleanup; a cancelled runner would
                    // otherwise skip ssh -O exit and leave a control master behind.
                    let cleanup = Task { try? await client.disconnect() }
                    await cleanup.value
                    clearPendingConnection()
                }
                if !isDisconnecting && !(error is CancellationError) {
                    errorMessage = error.localizedDescription
                    statusMessage = error.localizedDescription
                }
            }
            activeOperation = nil
            isLoading = false
        }
    }

    private func runDownload(_ operation: @escaping @MainActor () async throws -> Void) {
        guard isConnected, !isBusy else {
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
                finishPendingDownloads(status: .failed(error.localizedDescription))
                downloadQueue.removeAll()
            }
            let shouldContinueQueue = isConnected && !isDisconnecting && !downloadQueue.isEmpty
            activeDownloadTaskID = nil
            activeDownloadOperation = nil
            activeDownloadControl = nil
            isDownloading = false
            if shouldContinueQueue { runDownloadQueue() }
        }
    }

    private func markActiveDownloadCancelled() {
        if let activeDownloadTaskID {
            updateTask(activeDownloadTaskID, status: .cancelled)
        }
        if case .downloading(let itemName) = downloadState {
            downloadState = .cancelled(itemName)
        } else if case .paused(let itemName) = downloadState {
            downloadState = .cancelled(itemName)
        }
        statusMessage = AppLanguage.text("status.downloadCancelled")
    }

    private func finishPendingDownloads(status: DownloadTask.Status) {
        for index in downloadTasks.indices {
            if downloadTasks[index].status == .queued || downloadTasks[index].status == .downloading || downloadTasks[index].status == .paused {
                downloadTasks[index].finish(status: status)
            }
        }
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
