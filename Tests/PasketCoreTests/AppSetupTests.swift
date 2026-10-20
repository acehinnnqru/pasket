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
        setup.finishShortcutSetup(hasShortcut: false)
        #expect(!defaults.bool(forKey: "invocationShortcutSetupCompleted"))
        clipboardAllowed = true
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .accessibility)
        pasteAllowed = true
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .shortcut)
        pasteAllowed = false
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .accessibility)
    }

    @Test func menuBarChoicePersistsWithoutAssigningAShortcut() throws {
        let suite = "PasketSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .shortcut)
        setup.finishShortcutSetup(hasShortcut: false)
        #expect(setup.step == .complete)
        let relaunched = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        relaunched.refresh(hasShortcut: false)
        #expect(relaunched.step == .complete)
        #expect(GlobalShortcutManager(defaults: defaults).shortcut == nil)
    }

    @Test func existingShortcutSkipsRecordingAndLaterClearingDoesNotRepeatSetup() throws {
        let suite = "PasketSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { true })
        setup.refresh(hasShortcut: true)
        #expect(setup.step == .complete)
        setup.refresh(hasShortcut: false)
        #expect(setup.step == .complete)
        let revoked = AppSetup(defaults: defaults, clipboardAllowed: { true }, pasteAllowed: { false })
        revoked.refresh(hasShortcut: true)
        #expect(revoked.step == .accessibility)
    }
}
