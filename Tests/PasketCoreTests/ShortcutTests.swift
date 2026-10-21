import AppKit
import Carbon.HIToolbox
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct ShortcutTests {
    @Test func failedActiveQueueRegistrationDoesNotSaveTheShortcutDraft() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        #expect(manager.setPasteQueueActive(true))
        manager.beginRecording(.pasteNext)
        manager.record(try keyEvent(code: kVK_ANSI_V, modifiers: [.command, .option], characters: "v"))
        #expect(!manager.saveRecording())
        #expect(manager.isRecording)
        #expect(manager.errorMessage != nil)
        #expect(manager.pasteNextShortcut == nil)
        #expect(GlobalShortcutManager(defaults: defaults).pasteNextShortcut == nil)
        manager.cancelRecording()
        manager.setPasteQueueActive(false)
    }

    @Test func pasteNextIsOptionalAndOnlySavesARecordedDraftOnConfirmation() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        #expect(manager.pasteNextShortcut == nil)
        manager.beginRecording(.pasteNext)
        manager.record(try keyEvent(code: kVK_ANSI_V, modifiers: [.command, .option], characters: "v"))
        #expect(GlobalShortcutManager(defaults: defaults).pasteNextShortcut == nil)
        #expect(manager.saveRecording())
        #expect(GlobalShortcutManager(defaults: defaults).pasteNextShortcut?.displayName == "⌥⌘V")
        manager.beginRecording(.pasteNext)
        manager.stageShortcut(nil)
        manager.cancelRecording()
        #expect(manager.pasteNextShortcut != nil)
        manager.beginRecording(.pasteNext)
        manager.stageShortcut(nil)
        #expect(manager.saveRecording())
        #expect(GlobalShortcutManager(defaults: defaults).pasteNextShortcut == nil)
    }

    @Test func pasteNextPreservesNormalPasteAndRejectsEveryPasketConflict() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = GlobalShortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey), keyLabel: "P")
        defaults.set(try JSONEncoder().encode(history), forKey: "globalInvocationShortcut")
        let manager = GlobalShortcutManager(defaults: defaults)
        let deletion = GlobalShortcut(keyCode: UInt32(kVK_Delete), modifiers: UInt32(cmdKey | optionKey), keyLabel: "⌫")
        #expect(manager.setDeletionShortcut(deletion))
        for candidate in [history, deletion, .defaultSettings,
                          GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey), keyLabel: "V")] {
            #expect(!manager.setPasteNextShortcut(candidate))
            #expect(manager.pasteNextShortcut == nil)
        }
        let next = GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey), keyLabel: "V")
        #expect(manager.setPasteNextShortcut(next))
        #expect(!manager.setSettingsShortcut(next))
        #expect(!manager.setDeletionShortcut(next))
        manager.beginRecording(.showHistory)
        manager.stageShortcut(next)
        #expect(!manager.saveRecording())
        #expect(manager.errorMessage?.contains("Paste Next") == true)
        manager.cancelRecording()
        #expect(GlobalShortcutManager(defaults: defaults).pasteNextShortcut == next)
    }

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
        #expect(restored.shortcut == nil)
        #expect(restored.setDeletionShortcut(nil))
        #expect(GlobalShortcutManager(defaults: defaults).deletionShortcut == nil)
    }

    @Test func deletionCannotReplaceTheHistoryInvocationShortcut() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = GlobalShortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey), keyLabel: "P")
        defaults.set(try JSONEncoder().encode(history), forKey: "globalInvocationShortcut")
        let manager = GlobalShortcutManager(defaults: defaults)
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey), keyLabel: "D")
        #expect(manager.setDeletionShortcut(shortcut))
        let conflict = GlobalShortcut(keyCode: history.keyCode, modifiers: history.modifiers, keyLabel: "Different Label")
        #expect(!manager.setDeletionShortcut(conflict))
        #expect(manager.errorMessage != nil)
        #expect(manager.deletionShortcut == shortcut)
        #expect(GlobalShortcutManager(defaults: defaults).deletionShortcut == shortcut)
    }

    @Test func settingsDefaultsToCommandCommaAndPersistsChangesAndClearing() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        let comma = try keyEvent(code: kVK_ANSI_Comma, modifiers: .command, characters: ",")
        #expect(manager.settingsShortcut?.matches(comma) == true)
        #expect(manager.settingsShortcut?.displayName == "⌘,")

        let custom = GlobalShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | optionKey), keyLabel: "S")
        #expect(manager.setSettingsShortcut(custom))
        #expect(!manager.settingsShortcut!.matches(comma))
        #expect(GlobalShortcutManager(defaults: defaults).settingsShortcut == custom)
        #expect(manager.setSettingsShortcut(nil))
        #expect(GlobalShortcutManager(defaults: defaults).settingsShortcut == nil)
        #expect(manager.setSettingsShortcut(.defaultSettings))
        #expect(GlobalShortcutManager(defaults: defaults).settingsShortcut == .defaultSettings)
    }

    @Test func settingsAndDeletionRejectConflictsWithoutChangingSavedBindings() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = GlobalShortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey), keyLabel: "P")
        defaults.set(try JSONEncoder().encode(history), forKey: "globalInvocationShortcut")
        let manager = GlobalShortcutManager(defaults: defaults)
        #expect(!manager.setSettingsShortcut(history))
        #expect(!manager.setDeletionShortcut(.defaultSettings))
        #expect(manager.deletionShortcut == nil)
        let deletion = GlobalShortcut(keyCode: UInt32(kVK_Delete), modifiers: UInt32(cmdKey | optionKey), keyLabel: "⌫")
        #expect(manager.setDeletionShortcut(deletion))
        #expect(!manager.setSettingsShortcut(deletion))
        #expect(manager.settingsShortcut == .defaultSettings)
        let restored = GlobalShortcutManager(defaults: defaults)
        #expect(restored.settingsShortcut == .defaultSettings)
        #expect(restored.deletionShortcut == deletion)
    }

    @Test func introducingSettingsPreservesExistingCommandCommaBindings() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = try JSONEncoder().encode(GlobalShortcut.defaultSettings)
        defaults.set(data, forKey: "deleteSelectedItemShortcut")
        let manager = GlobalShortcutManager(defaults: defaults)
        #expect(manager.settingsShortcut == nil)
        #expect(manager.deletionShortcut == .defaultSettings)
        #expect(!manager.setSettingsShortcut(.defaultSettings))
        #expect(manager.setDeletionShortcut(nil))
        #expect(manager.setSettingsShortcut(.defaultSettings))

        defaults.removeObject(forKey: "deleteSelectedItemShortcut")
        defaults.set(data, forKey: "globalInvocationShortcut")
        let restored = GlobalShortcutManager(defaults: defaults)
        #expect(restored.shortcut == .defaultSettings)
        #expect(restored.settingsShortcut == nil)
    }

    @Test func historyStartsUnassignedAndRecordingDoesNotSaveIt() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        #expect(manager.shortcut == nil)
        manager.beginRecording()
        #expect(!manager.canSaveRecording)
        manager.record(try keyEvent(code: kVK_ANSI_V, modifiers: [.command, .option], characters: "v"))
        #expect(manager.pendingShortcut?.displayName == "⌥⌘V")
        #expect(manager.canSaveRecording)
        #expect(manager.isRecording)
        #expect(manager.shortcut == nil)
        #expect(defaults.object(forKey: "globalInvocationShortcut") == nil)
        manager.cancelRecording()
        #expect(manager.pendingShortcut == nil)
        #expect(!manager.isRecording)
        #expect(GlobalShortcutManager(defaults: defaults).shortcut == nil)
    }

    @Test func settingsRecordingCanBeReplacedAndOnlySavesOnConfirmation() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        manager.beginRecording(.openSettings)
        manager.record(try keyEvent(code: kVK_ANSI_S, modifiers: [.command, .option], characters: "s"))
        manager.record(try keyEvent(code: kVK_ANSI_D, modifiers: [.command, .option], characters: "d"))
        #expect(manager.pendingShortcut?.displayName == "⌥⌘D")
        #expect(GlobalShortcutManager(defaults: defaults).settingsShortcut == .defaultSettings)
        #expect(manager.saveRecording())
        #expect(!manager.isRecording)
        #expect(GlobalShortcutManager(defaults: defaults).settingsShortcut?.displayName == "⌥⌘D")
    }

    @Test func clearingHistoryRequiresConfirmationAndCancellationPreservesSavedKeys() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = GlobalShortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey), keyLabel: "P")
        defaults.set(try JSONEncoder().encode(history), forKey: "globalInvocationShortcut")
        let manager = GlobalShortcutManager(defaults: defaults)
        manager.beginRecording()
        manager.stageShortcut(nil)
        #expect(manager.isClearingShortcut)
        #expect(GlobalShortcutManager(defaults: defaults).shortcut == history)
        manager.cancelRecording()
        #expect(manager.shortcut == history)
        #expect(GlobalShortcutManager(defaults: defaults).shortcut == history)
        manager.beginRecording()
        manager.stageShortcut(nil)
        #expect(manager.saveRecording())
        #expect(manager.shortcut == nil)
        #expect(GlobalShortcutManager(defaults: defaults).shortcut == nil)
    }

    @Test func conflictingDraftStaysVisibleAndPreservesBindingsUntilCorrected() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        manager.beginRecording(.deleteSelectedItem)
        manager.stageShortcut(.defaultSettings)
        #expect(!manager.saveRecording())
        #expect(manager.isRecording)
        #expect(manager.pendingShortcut == .defaultSettings)
        #expect(manager.errorMessage != nil)
        #expect(GlobalShortcutManager(defaults: defaults).deletionShortcut == nil)
        manager.record(try keyEvent(code: kVK_Delete, modifiers: [.command, .option], characters: "\u{7f}"))
        #expect(manager.saveRecording())
        #expect(GlobalShortcutManager(defaults: defaults).deletionShortcut?.displayName == "⌥⌘⌫")
    }

    @Test func failedHistoryRegistrationDoesNotSaveOrCloseRecording() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        manager.beginRecording()
        manager.record(try keyEvent(code: kVK_ANSI_V, modifiers: [.command, .option], characters: "v"))
        #expect(!manager.saveRecording())
        #expect(manager.isRecording)
        #expect(manager.pendingShortcut?.displayName == "⌥⌘V")
        #expect(manager.errorMessage != nil)
        #expect(GlobalShortcutManager(defaults: defaults).shortcut == nil)
    }

    @Test func invalidKeysCannotConfirmAPreviouslyRecordedCombination() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        manager.beginRecording(.openSettings)
        manager.record(try keyEvent(code: kVK_ANSI_S, modifiers: .command, characters: "s"))
        manager.record(try keyEvent(code: kVK_ANSI_D, modifiers: [], characters: "d"))
        #expect(!manager.canSaveRecording)
        #expect(!manager.saveRecording())
        #expect(manager.settingsShortcut == .defaultSettings)
    }

    private func keyEvent(code: Int, modifiers: NSEvent.ModifierFlags, characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code)
        ))
    }
}
