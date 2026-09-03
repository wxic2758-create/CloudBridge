import SwiftUI

extension Color {
    static let bridgeAccent = Color(red: 0.149, green: 0.659, blue: 0.941)
}

@main
struct CloudBridgeApp: App {
    @State private var model = BrowserModel()

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 660)
                .tint(.bridgeAccent)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
