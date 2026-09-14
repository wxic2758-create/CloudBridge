import Foundation

enum DownloadState: Equatable {
    case idle
    case downloading(String)
    case completed(String)
    case cancelled(String)
    case failed(String)
}

/// Bytes are the logical length written locally, not wire traffic (or fsync durability).
/// OpenSSH suppresses its terminal meter on pipes; do not parse it for progress.
struct DownloadProgress: Sendable, Equatable {
    let bytesTransferred: Int64?
    let totalBytes: Int64?
    let speedBytesPerSecond: Double?
    let estimatedRemainingSeconds: TimeInterval?

    var fraction: Double? {
        guard let bytesTransferred, let totalBytes, totalBytes > 0 else { return nil }
        // Only successful process completion may mark a task complete.
        return min(Double(bytesTransferred) / Double(totalBytes), 0.999)
    }
}

enum CompactFileSizeFormatter {
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    static func string(fromByteCount bytes: Int64, locale: Locale = .current) -> String {
        var value = Double(max(0, bytes))
        var unitIndex = 0
        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = unitIndex > 0 && value < 10 ? 1 : 0
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(Int(value))) \(units[unitIndex])"
    }
}

struct DownloadProgressSampler: Sendable {
    private var total: Int64?
    private var previousBytes: Int64 = 0
    private var previousTime: TimeInterval

    init(totalBytes: Int64?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        total = totalBytes.flatMap { $0 >= 0 ? $0 : nil }
        previousTime = now
    }

    mutating func sample(bytes: Int64?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> DownloadProgress {
        guard let bytes, bytes >= 0 else {
            return DownloadProgress(bytesTransferred: nil, totalBytes: total, speedBytesPerSecond: nil, estimatedRemainingSeconds: nil)
        }
        // A stale listing or truncation makes the advertised total unreliable.
        if bytes < previousBytes || bytes > (total ?? Int64.max) { total = nil }
        let elapsed = now - previousTime
        let speed = elapsed > 0 && bytes >= previousBytes ? Double(bytes - previousBytes) / elapsed : nil
        previousTime = now
        previousBytes = bytes
        let eta: TimeInterval?
        if let total, let speed, speed > 0, total > bytes {
            eta = Double(total - bytes) / speed
        } else {
            eta = nil
        }
        return DownloadProgress(bytesTransferred: bytes, totalBytes: total, speedBytesPerSecond: speed, estimatedRemainingSeconds: eta)
    }

    /// The caller supplies a fresh, private staging path, never an existing destination.
    /// Await the monitor on every exit so it cannot outlive the transfer/access grant.
    static func monitor(
        file: URL,
        totalBytes: Int64?,
        progress: (@Sendable (DownloadProgress) async -> Void)?,
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        let monitor = Task {
            var sampler = DownloadProgressSampler(totalBytes: totalBytes)
            while !Task.isCancelled {
                await progress?(sampler.sample(bytes: fileSize(at: file)))
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { break }
            }
            return sampler
        }
        do {
            try await operation()
            try Task.checkCancellation()
            monitor.cancel()
            // Preserve invalidated totals (growth/truncation) in the final sample.
            var finalSampler = await monitor.value
            let final = finalSampler.sample(bytes: fileSize(at: file))
            await progress?(DownloadProgress(bytesTransferred: final.bytesTransferred, totalBytes: final.totalBytes,
                                             speedBytesPerSecond: nil, estimatedRemainingSeconds: nil))
        } catch {
            monitor.cancel()
            _ = await monitor.value
            throw error
        }
    }

    static func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        return (attributes[.size] as? NSNumber)?.int64Value
    }
}

struct DownloadTask: Identifiable, Equatable, Codable {
    enum Status: Equatable, Codable {
        case queued
        case downloading
        case completed
        case cancelled
        case failed(String)
    }

    let id: UUID
    let itemName: String
    let remotePath: String
    let serverName: String
    let serverID: UUID?
    let isDirectory: Bool
    let remoteSize: Int64?
    let remoteModifiedAt: Date?
    var destination: URL?
    var status: Status
    var progress: Double?
    var bytesTransferred: Int64?
    var totalBytes: Int64?
    var speedBytesPerSecond: Double?
    var estimatedRemainingSeconds: TimeInterval?
    var completedAt: Date?

    var destinationExists: Bool {
        guard status == .completed, let destination else { return false }
        return FileManager.default.fileExists(atPath: destination.path)
    }

    func belongs(to id: UUID?) -> Bool {
        // Missing identity must never authorize a retry by display name (or nil == nil).
        guard let serverID, let id else { return false }
        return serverID == id
    }

    func remoteMetadataMatches(_ item: RemoteItem) -> Bool? {
        var compared = false
        if let remoteSize, let currentSize = item.size {
            compared = true
            if remoteSize != currentSize { return false }
        }
        if let remoteModifiedAt, let currentModifiedAt = item.modifiedAt {
            compared = true
            if abs(remoteModifiedAt.timeIntervalSince(currentModifiedAt)) > 1 { return false }
        }
        return compared ? true : nil
    }

    mutating func apply(_ sample: DownloadProgress) {
        guard status == .downloading else { return }
        bytesTransferred = sample.bytesTransferred
        totalBytes = sample.totalBytes
        progress = sample.fraction
        speedBytesPerSecond = sample.speedBytesPerSecond
        estimatedRemainingSeconds = sample.estimatedRemainingSeconds
    }

    mutating func start() {
        guard status == .queued else { return }
        status = .downloading
    }

    mutating func finish(status: Status, destination: URL? = nil) {
        let canFinish = self.status == .downloading ||
            (self.status == .queued && (status == .cancelled || status.isFailure))
        guard canFinish, status != .downloading, status != .queued else { return }
        self.status = status
        self.destination = destination
        speedBytesPerSecond = nil
        estimatedRemainingSeconds = nil
        if status == .completed {
            progress = 1
            completedAt = Date()
        }
    }

    init(
        itemName: String,
        remotePath: String,
        serverName: String,
        isDirectory: Bool,
        serverID: UUID? = nil,
        remoteSize: Int64? = nil,
        remoteModifiedAt: Date? = nil,
        status: Status = .downloading
    ) {
        self.id = UUID()
        self.itemName = itemName
        self.remotePath = remotePath
        self.serverName = serverName
        self.serverID = serverID
        self.isDirectory = isDirectory
        self.remoteSize = remoteSize
        self.remoteModifiedAt = remoteModifiedAt
        self.destination = nil
        self.status = status
        self.progress = nil
        self.bytesTransferred = nil
        self.totalBytes = nil
        self.speedBytesPerSecond = nil
        self.estimatedRemainingSeconds = nil
        self.completedAt = nil
    }
}

enum DownloadHistoryStore {
    private static let storageKey = "downloadHistory"
    private static let limit = 500

    static func load(defaults: UserDefaults = .standard) -> [DownloadTask] {
        guard let data = defaults.data(forKey: storageKey),
              let tasks = try? JSONDecoder().decode([DownloadTask].self, from: data) else {
            return []
        }
        return tasks.filter { $0.status == .completed }
    }

    static func save(_ tasks: [DownloadTask], defaults: UserDefaults = .standard) {
        let completed = Array(tasks.filter { $0.status == .completed }.prefix(limit))
        guard let data = try? JSONEncoder().encode(completed) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

private extension DownloadTask.Status {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
