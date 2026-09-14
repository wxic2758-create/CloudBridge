import SwiftUI

@main
struct CloudBridgeApp: App {
    @State private var model = BrowserModel()
    @State private var language = AppLanguage.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(model)
                .environment(\.locale, Locale(identifier: AppLanguage.resolved(language.selection)))
                .environment(\.layoutDirection, AppLanguage.isRTL(language.selection) ? .rightToLeft : .leftToRight)
                .frame(minWidth: 1120, minHeight: 650)
                .tint(Color.bridgeAccent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1320, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
