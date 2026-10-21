import Carbon.HIToolbox
import Testing
@testable import PasketCore

@MainActor
struct PasteShortcutResolverTests {
    @Test func readsTheRemappedPasteCommandInsteadOfAssumingCommandV() {
        let commands = [
            PasteShortcutResolver.MenuCommand(title: "Paste and Match Style", virtualKey: kVK_ANSI_V,
                                               modifiers: 3, character: "v"),
            PasteShortcutResolver.MenuCommand(title: "Paste", virtualKey: kVK_ANSI_Y,
                                               modifiers: 12, character: "y")
        ]
        let shortcut = PasteShortcutResolver.shortcut(from: commands)
        #expect(shortcut?.keyCode == UInt32(kVK_ANSI_Y))
        #expect(shortcut?.modifiers == UInt32(controlKey))
        #expect(shortcut?.displayName == "⌃Y")
        #expect(shortcut?.eventFlags == .maskControl)
    }

    @Test func usesTheLocalizedStandardTitleOrAnExplicitPasteIdentifier() {
        let chinese = PasteShortcutResolver.MenuCommand(title: "粘贴", virtualKey: kVK_ANSI_Y,
                                                         modifiers: 12, character: "y")
        #expect(PasteShortcutResolver.shortcut(from: [chinese])?.displayName == "⌃Y")
        let localized = PasteShortcutResolver.MenuCommand(title: "Localized Paste", virtualKey: kVK_ANSI_V,
                                                           modifiers: 5, character: "v")
        #expect(PasteShortcutResolver.shortcut(from: [localized]) == nil)
        let shortcut = PasteShortcutResolver.shortcut(from: [localized], pasteTitles: ["Localized Paste"])
        #expect(shortcut?.modifiers == UInt32(cmdKey | controlKey | shiftKey))
        #expect(shortcut?.eventFlags == [.maskCommand, .maskControl, .maskShift])
        let identified = PasteShortcutResolver.MenuCommand(title: "Other Title", identifier: "paste:",
                                                            virtualKey: kVK_ANSI_V, modifiers: 2, character: "v")
        #expect(PasteShortcutResolver.shortcut(from: [identified])?.eventFlags == [.maskCommand, .maskAlternate])
    }

    @Test func ambiguousOrInvalidMenusRequireTheFallbackInsteadOfGuessing() {
        let paste = PasteShortcutResolver.MenuCommand(title: "Paste", virtualKey: kVK_ANSI_V, modifiers: 0, character: "v")
        let other = PasteShortcutResolver.MenuCommand(title: "Paste", virtualKey: kVK_ANSI_Y, modifiers: 0, character: "y")
        #expect(PasteShortcutResolver.shortcut(from: [paste, other]) == nil)
        #expect(PasteShortcutResolver.shortcut(from: [paste, paste]) == .defaultPaste)
        #expect(PasteShortcutResolver.shortcut(from: [
            .init(title: "Paste", virtualKey: -1, modifiers: 0, character: "v"),
            .init(title: "Paste", virtualKey: 9, modifiers: 16, character: "v")
        ]) == nil)
    }
}
