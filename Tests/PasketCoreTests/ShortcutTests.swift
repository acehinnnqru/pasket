import AppKit
import Carbon.HIToolbox
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct ShortcutTests {
    @Test func shortcutMatchesKeysAndModifiersInsteadOfDisplayLabels() throws {
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey), keyLabel: "Custom Label")
        let event = try keyEvent(code: kVK_ANSI_D, modifiers: [.command, .capsLock], characters: "d")
        #expect(shortcut.matches(event))
        #expect(!shortcut.matches(try keyEvent(code: kVK_ANSI_D, modifiers: [.command, .shift], characters: "D")))
        #expect(!shortcut.matches(try keyEvent(code: kVK_ANSI_F, modifiers: .command, characters: "f")))
        #expect(!shortcut.matches(try keyEvent(code: kVK_ANSI_D, modifiers: [], characters: "d")))
    }

    @Test func deletionShortcutIsDisabledByDefaultAndPersistsUntilCleared() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        #expect(manager.deletionShortcut == nil)

        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_Delete), modifiers: UInt32(cmdKey | optionKey), keyLabel: "⌫")
        #expect(manager.setDeletionShortcut(shortcut))
        let restored = GlobalShortcutManager(defaults: defaults)
        #expect(restored.deletionShortcut == shortcut)
        #expect(restored.shortcut == .default)
        #expect(restored.setDeletionShortcut(nil))
        #expect(GlobalShortcutManager(defaults: defaults).deletionShortcut == nil)
    }

    @Test func deletionCannotReplaceTheHistoryInvocationShortcut() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey), keyLabel: "D")
        #expect(manager.setDeletionShortcut(shortcut))
        let conflict = GlobalShortcut(keyCode: manager.shortcut.keyCode, modifiers: manager.shortcut.modifiers, keyLabel: "Different Label")
        #expect(!manager.setDeletionShortcut(conflict))
        #expect(manager.errorMessage != nil)
        #expect(manager.deletionShortcut == shortcut)
        #expect(GlobalShortcutManager(defaults: defaults).deletionShortcut == shortcut)
    }

    private func keyEvent(code: Int, modifiers: NSEvent.ModifierFlags, characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code)
        ))
    }
}
