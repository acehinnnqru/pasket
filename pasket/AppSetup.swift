import AppKit
import Observation

@MainActor @Observable
final class AppSetup {
    enum Step { case clipboard, accessibility, shortcut, complete }

    private(set) var step: Step = .clipboard
    private(set) var needsClipboardAccess = false
    private(set) var needsPasteAccess = false
    private(set) var neverAskForShortcut: Bool
    var canContinue: Bool { !needsClipboardAccess && !needsPasteAccess }
    private let defaults: UserDefaults
    private let clipboardAllowed: () -> Bool
    private let pasteAllowed: () -> Bool
    private var dismissedShortcutPrompt = false
    private static let reminderKey = "neverAskForInvocationShortcut"

    init(defaults: UserDefaults = .standard,
         clipboardAllowed: @escaping () -> Bool = { NSPasteboard.general.accessBehavior == .alwaysAllow },
         pasteAllowed: @escaping () -> Bool = { CGPreflightPostEventAccess() }) {
        self.defaults = defaults
        neverAskForShortcut = defaults.bool(forKey: Self.reminderKey)
        self.clipboardAllowed = clipboardAllowed
        self.pasteAllowed = pasteAllowed
    }

    func refresh(hasShortcut: Bool) {
        needsClipboardAccess = !clipboardAllowed()
        needsPasteAccess = !pasteAllowed()
        if needsClipboardAccess {
            step = .clipboard
        } else if needsPasteAccess {
            step = .accessibility
        } else if !hasShortcut && !neverAskForShortcut && !dismissedShortcutPrompt {
            step = .shortcut
        } else {
            step = .complete
        }
    }

    @discardableResult
    func finishShortcutSetup(hasShortcut: Bool, neverAskAgain: Bool = false) -> Bool {
        refresh(hasShortcut: hasShortcut)
        guard canContinue else { return false }
        neverAskForShortcut = neverAskAgain
        defaults.set(neverAskAgain, forKey: Self.reminderKey)
        dismissedShortcutPrompt = true
        refresh(hasShortcut: hasShortcut)
        return step == .complete
    }
}
