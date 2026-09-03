import Foundation

enum DownloadState: Equatable {
    case idle
    case downloading(String)
    case completed(String)
    case failed(String)
}

struct DownloadTask: Identifiable, Equatable {
    enum Status: Equatable {
        case downloading
        case completed
        case failed(String)
    }

    let id: UUID
    let itemName: String
    let remotePath: String
    let serverName: String
    var destination: URL?
    var status: Status

    init(itemName: String, remotePath: String, serverName: String) {
        self.id = UUID()
        self.itemName = itemName
        self.remotePath = remotePath
        self.serverName = serverName
        self.destination = nil
        self.status = .downloading
    }
}
