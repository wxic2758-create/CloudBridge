import Foundation

struct FolderSizeResult: Codable, Sendable, Equatable {
    var bytes: Int64 = 0
    var isComplete = true
    var measuredAt = Date()
}

enum FolderSizeCalculator {
    // Serial requests keep recursive scans from flooding the server.
    static func calculate(
        path: String,
        isolation: isolated (any Actor)? = #isolation,
        list: (String) async throws -> [RemoteItem]
    ) async throws -> FolderSizeResult {
        var result = FolderSizeResult()
        var pending = [path]
        var visited = Set<String>()
        while let directory = pending.popLast() {
            try Task.checkCancellation()
            guard visited.insert(directory).inserted else { continue }
            guard visited.count <= 10_000 else {
                result.isComplete = false
                break
            }
            do {
                let items = try await list(directory)
                for item in items where item.name != "." && item.name != ".." {
                    if item.isDirectory {
                        pending.append(item.path)
                    } else if item.kind == .file, let size = item.size, size >= 0 {
                        let sum = result.bytes.addingReportingOverflow(size)
                        if sum.overflow { result.isComplete = false }
                        else { result.bytes = sum.partialValue }
                    } else {
                        result.isComplete = false
                    }
                }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                if let error = error as? ProcessRunnerError, error == .cancelled { throw error }
                result.isComplete = false
            }
        }
        try Task.checkCancellation()
        result.measuredAt = Date()
        return result
    }
}

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

    /// Finder hides names beginning with a dot. Keep the remote name recognizable
    /// while making downloaded files discoverable in the chosen local folder.
    var localDownloadName: String {
        name.hasPrefix(".") ? "_\(name)" : name
    }

    var systemImageName: String {
        switch kind {
        case .directory:
            "folder"
        case .file:
            fileSystemImageName
        case .symlink:
            "arrow.triangle.branch"
        case .unknown:
            "doc"
        }
    }


    private var fileSystemImageName: String {
        let pathExtension = (name as NSString).pathExtension.lowercased()
        return switch pathExtension {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "svg", "raw":
            "photo"
        case "mov", "mp4", "m4v", "avi", "mkv", "webm", "mpeg", "mpg":
            "film"
        case "mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg":
            "waveform"
        case "pdf":
            "doc.richtext"
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            "archivebox"
        case "swift", "c", "h", "m", "mm", "cpp", "hpp", "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "java", "kt", "sh", "html", "css":
            "chevron.left.forwardslash.chevron.right"
        case "txt", "md", "rtf", "log", "json", "xml", "yaml", "yml", "toml", "ini", "conf":
            "doc.text"
        case "csv", "xls", "xlsx", "numbers":
            "tablecells"
        case "ppt", "pptx", "key":
            "rectangle.on.rectangle"
        case "dmg", "iso":
            "externaldrive"
        default:
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
