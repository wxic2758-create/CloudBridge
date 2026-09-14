import SwiftUI

enum AppSection: Hashable {
    case servers
    case downloads
}

@main
struct CloudBridgeApp: App {
    @State private var model = BrowserModel()
    @State private var language = AppLanguage.shared
    @State private var section = AppSection.servers

    var body: some Scene {
        WindowGroup {
            MainView(section: $section)
                .environment(model)
                .environment(\.locale, Locale(identifier: AppLanguage.resolved(language.selection)))
                .environment(\.layoutDirection, AppLanguage.isRTL(language.selection) ? .rightToLeft : .leftToRight)
                .frame(minWidth: 900, minHeight: 620)
                .tint(Color.bridgeAccent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1320, height: 800)
        .commands {
            CloudBridgeCommands(model: model, section: $section)
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(\.locale, Locale(identifier: AppLanguage.resolved(language.selection)))
                .environment(\.layoutDirection, AppLanguage.isRTL(language.selection) ? .rightToLeft : .leftToRight)
                .frame(minWidth: 600, idealWidth: 680, minHeight: 380, idealHeight: 500)
                .tint(Color.bridgeAccent)
        }
    }
}

private struct CloudBridgeCommands: Commands {
    let model: BrowserModel
    @Binding var section: AppSection

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(AppLanguage.text("action.addServer")) {
                section = .servers
                model.newServer()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(model.isBusy)
        }

        CommandMenu(AppLanguage.text("nav.servers")) {
            Button(AppLanguage.text("nav.servers")) {
                section = .servers
            }
            .keyboardShortcut("1", modifiers: .command)
            Divider()
            Button(AppLanguage.text("action.editServer"), action: model.editSelectedServer)
                .disabled(model.isConnected || model.isBusy || model.selectedServer == nil)
            Divider()
            Button(AppLanguage.text("action.connect"), action: model.connect)
                .disabled(model.isConnected || model.isBusy || model.selectedServer == nil)
            Button(AppLanguage.text("action.disconnect"), action: model.disconnect)
                .disabled(!model.isConnected || model.isBusy)
            Button(AppLanguage.text("action.refresh"), action: model.reload)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.isConnected || model.isBusy)
        }

        CommandMenu(AppLanguage.text("nav.tasks")) {
            Button(AppLanguage.text("nav.tasks")) {
                section = .downloads
            }
            .keyboardShortcut("2", modifiers: .command)
            Divider()
            Button(AppLanguage.text("action.preview")) {
                if let item = model.selectedItem { model.preview(item) }
            }
            .disabled(model.isBusy || model.selectedItems.count != 1 || model.selectedItem?.isDirectory != false)
            Button(AppLanguage.text("action.download"), action: model.downloadSelected)
                .disabled(!model.canQueueDownloads || model.selectedItems.isEmpty)
            Divider()
            Button(AppLanguage.text("tasks.clearCompleted"), action: model.clearDownloadHistory)
                .disabled(!model.hasDownloadHistory)
        }
    }
}
