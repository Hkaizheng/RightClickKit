import SwiftUI

@main
struct RightClickKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("RightClickKit", systemImage: "cursorarrow.click") {
            MenuBarMenuView(appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.menu)
    }
}
