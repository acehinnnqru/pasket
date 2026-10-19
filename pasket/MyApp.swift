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
            Button(appDelegate.controller.store.isPaused ? "Resume Collection" : "Pause Collection") {
                let store = appDelegate.controller.store
                store.setPaused(!store.isPaused)
            }
            .disabled(appDelegate.controller.store.isLoading || appDelegate.controller.store.isStorageBlocked)
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
