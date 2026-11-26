import AppKit
import SwiftUI

struct MenuBarMenuView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Group {
            Button("设置…") {
                appDelegate.showNewFileSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("打开 Finder 扩展设置") {
                appDelegate.openFinderExtensionSettings()
            }

            Divider()

            Toggle(
                "开机启动（\(appDelegate.launchAtLoginStatusDescription)）",
                isOn: Binding(
                    get: { appDelegate.launchAtLoginEnabled },
                    set: { appDelegate.setLaunchAtLogin($0) }
                )
            )

            Divider()

            Button("退出 RightClickKit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            appDelegate.refreshLaunchAtLoginStatus()
        }
    }
}
