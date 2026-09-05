import Foundation

enum DownloadState: Equatable {
    case idle
    case downloading(String)
    case completed(String)
    case cancelled(String)
    case failed(String)
}

struct DownloadTask: Identifiable, Equatable {
    enum Status: Equatable {
        case downloading
        case completed
        case cancelled
        case failed(String)
    }

    let id: UUID
    let itemName: String
    let remotePath: String
    let serverName: String
    let isDirectory: Bool
    var destination: URL?
    var status: Status
    var progress: Double?
    var bytesTransferred: Int64?
    var totalBytes: Int64?
    var speedBytesPerSecond: Double?
    var estimatedRemainingSeconds: TimeInterval?

    init(itemName: String, remotePath: String, serverName: String, isDirectory: Bool) {
        self.id = UUID()
        self.itemName = itemName
        self.remotePath = remotePath
        self.serverName = serverName
        self.isDirectory = isDirectory
        self.destination = nil
        self.status = .downloading
        self.progress = nil
        self.bytesTransferred = nil
        self.totalBytes = nil
        self.speedBytesPerSecond = nil
        self.estimatedRemainingSeconds = nil
    }
}
