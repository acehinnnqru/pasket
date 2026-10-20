import AppKit
import Observation

@MainActor @Observable
final class AppSetup {
    enum Step { case clipboard, accessibility, shortcut, complete }

    private(set) var step: Step = .clipboard
    private let defaults: UserDefaults
    private let clipboardAllowed: () -> Bool
    private let pasteAllowed: () -> Bool
    private static let completionKey = "invocationShortcutSetupCompleted"

    init(defaults: UserDefaults = .standard,
         clipboardAllowed: @escaping () -> Bool = { NSPasteboard.general.accessBehavior == .alwaysAllow },
         pasteAllowed: @escaping () -> Bool = { CGPreflightPostEventAccess() }) {
        self.defaults = defaults
        self.clipboardAllowed = clipboardAllowed
        self.pasteAllowed = pasteAllowed
    }

    func refresh(hasShortcut: Bool) {
        if hasShortcut { defaults.set(true, forKey: Self.completionKey) }
        if !clipboardAllowed() {
            step = .clipboard
        } else if !pasteAllowed() {
            step = .accessibility
        } else if !hasShortcut && !defaults.bool(forKey: Self.completionKey) {
            step = .shortcut
        } else {
            step = .complete
        }
    }

    func finishShortcutSetup(hasShortcut: Bool) {
        guard step == .shortcut else { return }
        defaults.set(true, forKey: Self.completionKey)
        refresh(hasShortcut: hasShortcut)
    }
}
