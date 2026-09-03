import Foundation

struct RemoteItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case directory
        case file
        case symlink
        case unknown
    }

    let id: String
    let name: String
    let path: String
    let kind: Kind
    let size: Int64?
    let modifiedAt: Date?

    var isDirectory: Bool {
        kind == .directory
    }

    var canTryOpen: Bool {
        kind == .directory || kind == .unknown
    }

    var systemImageName: String {
        switch kind {
        case .directory:
            "folder"
        case .file:
            "doc"
        case .symlink:
            "arrow.triangle.branch"
        case .unknown:
            "doc"
        }
    }
}

extension RemoteItem {
    static let parent = RemoteItem(
        id: "..",
        name: "..",
        path: "..",
        kind: .directory,
        size: nil,
        modifiedAt: nil
    )
}
