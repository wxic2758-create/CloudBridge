import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum FileTypeIconResolver {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for item: RemoteItem) -> NSImage? {
        switch item.kind {
        case .directory:
            return NSWorkspace.shared.icon(for: .folder)
        case .symlink:
            return nil
        case .unknown:
            return NSWorkspace.shared.icon(for: .data)
        case .file:
            let ext = (item.name as NSString).pathExtension.lowercased()
            guard !ext.isEmpty else { return NSWorkspace.shared.icon(for: .data) }
            if let cached = cache.object(forKey: ext as NSString) { return cached }
            let image = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
            cache.setObject(image, forKey: ext as NSString)
            return image
        }
    }
}

struct RemoteItemIcon: View {
    let item: RemoteItem

    var body: some View {
        if let image = FileTypeIconResolver.image(for: item) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: item.systemImageName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.bridgeAccent)
        }
    }
}
