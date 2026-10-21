import AppKit
import Carbon.HIToolbox
import Testing
@testable import PasketCore

@Suite(.serialized) @MainActor
struct ShortcutTests {
    @Test func firstQueueSetupDoesNotConfirmOrCaptureAKeyUntilSaved() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var registrations = 0
        let manager = GlobalShortcutManager(defaults: defaults, queueRegistration: { _, _ in
            registrations += 1
            return noErr
        })
        #expect(manager.needsPasteQueueShortcutSetup)
        manager.beginPasteQueueSetup()
        #expect(manager.isConfiguringPasteQueue)
        #expect(manager.recordingAction == .pasteNext)
        #expect(manager.canSaveRecording)
        #expect(manager.isClearingShortcut)
        #expect(registrations == 0)
        manager.cancelRecording()
        #expect(!manager.isConfiguringPasteQueue)
        #expect(manager.needsPasteQueueShortcutSetup)
        #expect(GlobalShortcutManager(defaults: defaults).needsPasteQueueShortcutSetup)
    }

    @Test func firstQueueSetupCanConfirmCommandVAndRememberFollowingTheApp() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var registrations: [GlobalShortcut] = []
        var removals = 0
        var registeredID: UInt32 = 0
        let manager = GlobalShortcutManager(defaults: defaults, queueRegistration: { shortcut, id in
            registrations.append(shortcut)
            registeredID = id
            return noErr
        }, queueUnregistration: { removals += 1 })
        manager.beginPasteQueueSetup()
        #expect(manager.saveRecording())
        #expect(registrations == [.defaultPaste])
        #expect(removals == 1)
        #expect(!manager.handleHotKey(id: registeredID, pressed: true))
        #expect(!manager.needsPasteQueueShortcutSetup)
        #expect(manager.pasteNextShortcut == nil)
        #expect(!GlobalShortcutManager(defaults: defaults).needsPasteQueueShortcutSetup)
    }

    @Test func firstQueueSetupKeepsTheDialogAndPreferencesUnchangedOnConflicts() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var registrationStatus = OSStatus(eventHotKeyExistsErr)
        let manager = GlobalShortcutManager(defaults: defaults, queueRegistration: { _, _ in registrationStatus })
        manager.beginPasteQueueSetup()
        #expect(!manager.saveRecording())
        #expect(manager.isRecording)
        #expect(manager.errorMessage?.contains("already be in use") == true)
        #expect(manager.needsPasteQueueShortcutSetup)
        #expect(GlobalShortcutManager(defaults: defaults).needsPasteQueueShortcutSetup)
        manager.stageShortcut(.defaultSettings)
        #expect(!manager.saveRecording())
        #expect(manager.errorMessage?.contains("conflicts") == true)
        registrationStatus = noErr
        let candidate = GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | optionKey), keyLabel: "N")
        manager.stageShortcut(candidate)
        #expect(manager.saveRecording())
        #expect(manager.pasteNextShortcut == candidate)
        #expect(!manager.needsPasteQueueShortcutSetup)
        #expect(GlobalShortcutManager(defaults: defaults).pasteNextShortcut == candidate)
    }

    @Test func existingCustomQueueShortcutsDoNotRequireFirstUseSetup() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidate = GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | optionKey), keyLabel: "N")
        defaults.set(try JSONEncoder().encode(candidate), forKey: "pasteNextShortcut")
        let manager = GlobalShortcutManager(defaults: defaults)
        #expect(!manager.needsPasteQueueShortcutSetup)
        #expect(manager.pasteNextShortcut == candidate)
    }

    @Test func commandVIsRegisteredOnlyForAnActiveQueueAndEachPressInvokesOnce() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var registrations: [GlobalShortcut] = []
        var activeID: UInt32 = 0
        var removals = 0
        let manager = GlobalShortcutManager(defaults: defaults, queueRegistration: { shortcut, id in
            registrations.append(shortcut)
            activeID = id
            return noErr
        }, queueUnregistration: { removals += 1 })
        var invocations = 0
        manager.onPasteNext = { invocations += 1 }
        #expect(manager.effectivePasteNextShortcut == .defaultPaste)
        #expect(registrations.isEmpty)
        #expect(manager.setPasteQueueActive(true))
        #expect(registrations == [.defaultPaste])
        #expect(manager.handleHotKey(id: activeID, pressed: true))
        #expect(manager.handleHotKey(id: activeID, pressed: true))
        #expect(invocations == 1)
        manager.handleHotKey(id: activeID, pressed: false)
        manager.handleHotKey(id: activeID, pressed: true)
        #expect(invocations == 2)
        manager.setPasteQueueActive(false)
        #expect(removals == 1)
        #expect(!manager.handleHotKey(id: activeID, pressed: true))
        #expect(invocations == 2)
    }

    @Test func queueFollowsDestinationChangesWhilePreservingACustomTrigger() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var registered: [GlobalShortcut] = []
        let manager = GlobalShortcutManager(defaults: defaults, queueRegistration: { shortcut, _ in
            registered.append(shortcut)
            return noErr
        })
        let remapped = GlobalShortcut(keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(controlKey), keyLabel: "Y")
        #expect(manager.updatePasteDestination(detectedShortcut: remapped))
        #expect(manager.effectivePasteNextShortcut == remapped)
        #expect(registered.isEmpty)
        #expect(manager.setPasteQueueActive(true))
        #expect(registered == [remapped])
        #expect(manager.updatePasteDestination(detectedShortcut: .defaultPaste))
        #expect(registered == [remapped, .defaultPaste])
        let custom = GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | optionKey), keyLabel: "N")
        #expect(manager.setPasteNextShortcut(custom))
        #expect(manager.updatePasteDestination(detectedShortcut: remapped))
        #expect(manager.resolvedPasteShortcut == remapped)
        #expect(manager.effectivePasteNextShortcut == custom)
        #expect(registered.last == custom)
        #expect(registered.count == 3)
        #expect(GlobalShortcutManager(defaults: defaults).pasteNextShortcut == custom)
        #expect(manager.setPasteNextShortcut(nil))
        #expect(registered.last == remapped)
        manager.setPasteQueueActive(false)
    }

    @Test func configuredFallbackIsUsedOnlyWhenMenuDetectionIsUnavailable() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        let fallback = GlobalShortcut(keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(controlKey), keyLabel: "Y")
        #expect(manager.setPasteFallbackShortcut(fallback))
        #expect(manager.updatePasteDestination(detectedShortcut: nil))
        #expect(manager.resolvedPasteShortcut == fallback)
        #expect(GlobalShortcutManager(defaults: defaults).pasteFallbackShortcut == fallback)
        #expect(manager.updatePasteDestination(detectedShortcut: .defaultPaste))
        #expect(manager.resolvedPasteShortcut == .defaultPaste)
        #expect(manager.setPasteFallbackShortcut(nil))
        #expect(manager.updatePasteDestination(detectedShortcut: nil))
        #expect(manager.resolvedPasteShortcut == .defaultPaste)
    }

    @Test func settingsCanUseNormalPasteWhileTheQueueRemainsActive() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var registrations = 0
        var removals = 0
        let manager = GlobalShortcutManager(defaults: defaults, queueRegistration: { _, _ in
            registrations += 1
            return noErr
        }, queueUnregistration: { removals += 1 })
        #expect(manager.setPasteQueueActive(true))
        manager.suspendPasteQueueShortcut()
        #expect(removals == 1)
        manager.beginRecording(.pasteNext)
        manager.stageShortcut(.defaultPaste)
        #expect(manager.saveRecording())
        #expect(registrations == 1)
        #expect(manager.updatePasteDestination(detectedShortcut: .defaultPaste))
        #expect(registrations == 2)
        manager.setPasteQueueActive(false)
        #expect(removals == 2)
    }

    @Test func failedActiveQueueRegistrationDoesNotSaveTheShortcutDraft() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcutManager(defaults: defaults)
        #expect(!manager.setPasteQueueActive(true))
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

    @Test func pasteNextAllowsCommandVAndRejectsEveryPasketConflict() throws {
        let suite = "PasketShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = GlobalShortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey), keyLabel: "P")
        defaults.set(try JSONEncoder().encode(history), forKey: "globalInvocationShortcut")
        let manager = GlobalShortcutManager(defaults: defaults)
        let deletion = GlobalShortcut(keyCode: UInt32(kVK_Delete), modifiers: UInt32(cmdKey | optionKey), keyLabel: "⌫")
        #expect(manager.setDeletionShortcut(deletion))
        for candidate in [history, deletion, .defaultSettings] {
            #expect(!manager.setPasteNextShortcut(candidate))
            #expect(manager.pasteNextShortcut == nil)
        }
        #expect(manager.setPasteNextShortcut(.defaultPaste))
        #expect(manager.effectivePasteNextShortcut == .defaultPaste)
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
