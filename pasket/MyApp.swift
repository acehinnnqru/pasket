import SwiftUI
import Carbon.HIToolbox

@main
struct PasketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Clipboard History") {
                appDelegate.controller.showPanel()
            }
            .keyboardShortcut(appDelegate.controller.shortcuts.shortcut?.menuKeyboardShortcut)
            if appDelegate.controller.shortcuts.shortcut == nil {
                Text("No shortcut set")
            }
            if let error = appDelegate.controller.shortcuts.errorMessage {
                Text(error)
            }
            if appDelegate.controller.store.pasteQueue.isActive {
                Divider()
                Text("Next: \(appDelegate.controller.store.pasteQueue.next?.title ?? "")")
                Text("\(appDelegate.controller.store.pasteQueue.remainingCount) remaining")
                Button("Paste Next\(appDelegate.controller.shortcuts.pasteNextShortcut.map { " (\($0.displayName))" } ?? "")") {
                    appDelegate.controller.pasteNextQueuedItem()
                }
                .disabled(appDelegate.controller.store.pasteQueue.isPasting)
                Button("Cancel Paste Queue") { appDelegate.controller.store.pasteQueue.cancel() }
            }
            Divider()
            Button(appDelegate.controller.store.clipboardAccessDenied ? "Allow Clipboard Access…"
                   : appDelegate.controller.store.isPaused ? "Resume Collection" : "Pause Collection") {
                let store = appDelegate.controller.store
                if store.clipboardAccessDenied {
                    appDelegate.controller.showPanel()
                    store.setPaused(false)
                } else {
                    store.setPaused(!store.isPaused)
                }
            }
            .disabled(appDelegate.controller.store.isLoading || appDelegate.controller.store.isStorageBlocked)
            #if DEBUG
            Toggle("Debug Mode", isOn: Binding(
                get: { appDelegate.controller.store.isDebugMode },
                set: { appDelegate.controller.store.setDebugMode($0) }
            ))
            .disabled(appDelegate.controller.store.isLoading || appDelegate.controller.store.isCopying)
            .help("Show sample data for screenshots")
            .accessibilityIdentifier("debugModeToggle")
            #endif
            Divider()
            Button("Statistics…") {
                appDelegate.controller.showStatistics()
            }
            .accessibilityIdentifier("openPasketStatistics")
            Button("Settings…") {
                appDelegate.controller.showSettings()
            }
            .keyboardShortcut(appDelegate.controller.shortcuts.settingsShortcut?.menuKeyboardShortcut)
            Divider()
            Button("Quit Pasket") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: PasketMenuIcon.image)
                if appDelegate.controller.store.pasteQueue.isActive {
                    Text("\(appDelegate.controller.store.pasteQueue.remainingCount)")
                }
            }.accessibilityLabel("Pasket")
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
