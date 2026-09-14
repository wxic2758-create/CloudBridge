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
