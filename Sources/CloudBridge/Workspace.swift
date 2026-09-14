import Foundation
import SwiftUI
import Observation

enum Workspace: String, CaseIterable, Identifiable {
    case servers, tasks, settings
    var id: Self { self }

    @MainActor
    var title: String { AppLanguage.text("nav.\(rawValue)", selection: AppLanguage.shared.selection) }

    var icon: String {
        switch self {
        case .servers: "server.rack"
        case .tasks: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }
}

enum ItemFilter: String, CaseIterable, Identifiable {
    case all, folders, files
    var id: Self { self }
    @MainActor
    var title: String { AppLanguage.text("filter.\(rawValue)", selection: AppLanguage.shared.selection) }
}

struct WorkspaceFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct DownloadFlight: Identifiable {
    let id = UUID()
    let symbol: String
    let source: CGPoint
    let destination: CGPoint
}

struct BrowseContext {
    let searchText: String
    let itemFilter: ItemFilter
    let selectedItemID: String?

    init(searchText: String, itemFilter: ItemFilter, selectedItemID: String?) {
        self.searchText = searchText
        self.itemFilter = itemFilter
        self.selectedItemID = selectedItemID
    }
}

/// Window navigation and browsing context. No view code belongs here.
@Observable @MainActor
final class WorkspaceSession {
    private(set) var workspace = Workspace.servers
    var searchText = ""
    var itemFilter = ItemFilter.all
    private(set) var downloadFlight: DownloadFlight?
    private(set) var downloadAcknowledged = false
    private(set) var feedbackID: UUID?
    private var frames: [String: CGRect] = [:]
    private var savedBrowseContext: BrowseContext?

    func navigate(to destination: Workspace, selectedItemID: String? = nil) {
        guard destination != workspace else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if workspace == .servers {
                savedBrowseContext = BrowseContext(searchText: searchText, itemFilter: itemFilter, selectedItemID: selectedItemID)
            }
            if destination == .servers, let context = savedBrowseContext {
                searchText = context.searchText
                itemFilter = context.itemFilter
            }
            downloadFlight = nil
            workspace = destination
        }
    }

    var savedSelectedID: String? { savedBrowseContext?.selectedItemID }
    func resetFilter() { searchText = ""; itemFilter = .all }
    func updateFrames(_ frames: [String: CGRect]) { self.frames = frames }

    func acknowledgeDownload(_ task: DownloadTask, reduceMotion: Bool, fromKeyboard: Bool) {
        feedbackID = UUID()
        downloadAcknowledged = true
        downloadFlight = nil
        guard !reduceMotion, !fromKeyboard, workspace == .servers,
              let source = frames["file:" + task.remotePath],
              let destination = frames["destination"],
              let browser = frames["browser"],
              browser.contains(CGPoint(x: source.midX, y: source.midY)),
              !source.isEmpty, !destination.isEmpty else { return }
        downloadFlight = DownloadFlight(
            symbol: task.isDirectory ? "folder.fill" : "doc.fill",
            source: CGPoint(x: source.midX, y: source.midY),
            destination: CGPoint(x: destination.midX, y: destination.midY)
        )
    }

    func suppressFlight() { downloadFlight = nil }

    func finishFeedback(_ id: UUID) {
        guard feedbackID == id else { return }
        downloadFlight = nil
        downloadAcknowledged = false
        feedbackID = nil
    }
}
