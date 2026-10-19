import SwiftUI

@main
struct PasketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Pasket", systemImage: "basket") {
            Button("Show Clipboard History") {
                appDelegate.controller.showPanel()
            }
            Text(appDelegate.controller.shortcuts.shortcut.displayName)
            if let error = appDelegate.controller.shortcuts.errorMessage {
                Text(error)
            }
            Divider()
            Button("Settings…") {
                appDelegate.controller.showSettings()
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit Pasket") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
