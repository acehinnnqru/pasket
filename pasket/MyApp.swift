import SwiftUI
import Carbon.HIToolbox

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
            .keyboardShortcut(appDelegate.controller.shortcuts.settingsShortcut?.menuKeyboardShortcut)
            Divider()
            Button("Quit Pasket") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}

private extension GlobalShortcut {
    var menuKeyboardShortcut: KeyboardShortcut? {
        let specialKeys: [UInt32: KeyEquivalent] = [
            UInt32(kVK_Space): .space, UInt32(kVK_Return): .return, UInt32(kVK_Tab): .tab,
            UInt32(kVK_Delete): .delete, UInt32(kVK_ForwardDelete): .deleteForward,
            UInt32(kVK_LeftArrow): .leftArrow, UInt32(kVK_RightArrow): .rightArrow,
            UInt32(kVK_UpArrow): .upArrow, UInt32(kVK_DownArrow): .downArrow,
            UInt32(kVK_Home): .home, UInt32(kVK_End): .end,
            UInt32(kVK_PageUp): .pageUp, UInt32(kVK_PageDown): .pageDown
        ]
        let key: KeyEquivalent
        if let special = specialKeys[keyCode] {
            key = special
        } else if keyLabel.hasPrefix("F"), let number = Int(keyLabel.dropFirst()),
                  (1...12).contains(number), let scalar = UnicodeScalar(0xF704 + number - 1) {
            key = KeyEquivalent(Character(String(scalar)))
        } else if keyLabel.lowercased().count == 1, let character = keyLabel.lowercased().first {
            key = KeyEquivalent(character)
        } else {
            return nil
        }
        var flags: SwiftUI.EventModifiers = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return KeyboardShortcut(key, modifiers: flags)
    }
}
