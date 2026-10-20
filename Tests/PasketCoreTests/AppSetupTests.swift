import Foundation
import Testing
@testable import PasketCore

@MainActor
struct AppSetupTests {
    @Test func permissionsPrecedeShortcutSetupAndAreRechecked() throws {
        let suite = "PasketSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var clipboardAllowed = false
        var pasteAllowed = false
        let setup = AppSetup(defaults: defaults, clipboardAllowed: { clipboardAllowed }, pasteAllowed: { pasteAllowed })
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .clipboard)
        #expect(setup.needsClipboardAccess)
        #expect(setup.needsPasteAccess)
        #expect(!setup.canContinue)
        #expect(!setup.finishShortcutSetup(hasShortcut: false, neverAskAgain: true))
        #expect(!defaults.bool(forKey: "neverAskForInvocationShortcut"))
        clipboardAllowed = true
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .accessibility)
        #expect(!setup.needsClipboardAccess)
        #expect(setup.needsPasteAccess)
        pasteAllowed = true
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .shortcut)
        #expect(setup.canContinue)
        pasteAllowed = false
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .accessibility)
    }

    @Test func skippingWithoutOptingOutOnlyDismissesTheCurrentLaunch() throws {
        let suite = "PasketSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .shortcut)
        setup.finishShortcutSetup(hasShortcut: false)
        #expect(setup.step == .complete)
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .complete)
        #expect(!setup.neverAskForShortcut)
        let relaunched = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        relaunched.refresh(hasShortcut: false)
        #expect(relaunched.step == .shortcut)
        #expect(GlobalShortcutManager(defaults: defaults).shortcut == nil)
    }

    @Test func existingShortcutSkipsTheGuideWithoutSilencingFutureReminders() throws {
        let suite = "PasketSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        setup.refresh(hasShortcut: true)
        #expect(setup.step == .complete)
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .shortcut)
        let revoked = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { false })
        revoked.refresh(hasShortcut: true)
        #expect(revoked.step == .accessibility)
    }

    @Test func neverAskAgainSurvivesRelaunchButDoesNotSuppressPermissionGuidance() throws {
        let suite = "PasketSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        setup.refresh(hasShortcut: false)
        #expect(setup.finishShortcutSetup(hasShortcut: false, neverAskAgain: true))
        let relaunched = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        relaunched.refresh(hasShortcut: false)
        #expect(relaunched.step == .complete)
        #expect(relaunched.neverAskForShortcut)
        let revoked = AppSetup(defaults: defaults, clipboardAllowed: { false }, pasteAllowed: { false })
        revoked.refresh(hasShortcut: false)
        #expect(revoked.needsClipboardAccess)
        #expect(revoked.needsPasteAccess)
        #expect(!revoked.canContinue)
        #expect(revoked.step == .clipboard)
    }

    @Test func reopeningAfterGrantingPermissionsRechecksTheSavedShortcut() throws {
        let suite = "PasketSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let before = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { false })
        before.refresh(hasShortcut: false)
        #expect(before.needsPasteAccess)
        let after = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        after.refresh(hasShortcut: false)
        #expect(!after.needsClipboardAccess)
        #expect(!after.needsPasteAccess)
        #expect(after.step == .shortcut)
        after.refresh(hasShortcut: true)
        #expect(after.step == .complete)
    }

    @Test func legacyCompletionDoesNotCountAsAnExplicitReminderOptOut() throws {
        let suite = "PasketSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "invocationShortcutSetupCompleted")
        let setup = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .shortcut)
        #expect(!setup.neverAskForShortcut)
    }
}
