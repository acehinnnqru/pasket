import AppKit
import Carbon.HIToolbox
import Observation

@MainActor @Observable
final class ClipboardPasteController {
    struct Target {
        let processIdentifier: pid_t
        let isActive: () -> Bool
        let isTerminated: () -> Bool
        let canRestoreFocus: () -> Bool

        var canPrepareForPaste: Bool { !isTerminated() && (isActive() || canRestoreFocus()) }

        init(application: NSRunningApplication, canRestoreFocus: @escaping () -> Bool = { false }) {
            processIdentifier = application.processIdentifier
            isActive = { application.isActive }
            isTerminated = { application.isTerminated }
            self.canRestoreFocus = canRestoreFocus
        }

        init(processIdentifier: pid_t, isActive: @escaping () -> Bool,
             isTerminated: @escaping () -> Bool, canRestoreFocus: @escaping () -> Bool = { false }) {
            self.processIdentifier = processIdentifier
            self.isActive = isActive
            self.isTerminated = isTerminated
            self.canRestoreFocus = canRestoreFocus
        }
    }

    private(set) var errorMessage: String? {
        didSet {
            toasts.show(needsPermission ? nil : errorMessage, source: .paste,
                        title: "Item Copied", style: .information)
        }
    }
    private(set) var needsPermission = false
    let toasts: PasketToastCenter
    let systemAccess: SystemAccessController
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private let hasAccess: () -> Bool
    @ObservationIgnored private let inputReleased: (UInt32?) -> Bool
    @ObservationIgnored private let clipboardChangeCount: () -> Int
    @ObservationIgnored private let postPaste: (pid_t, GlobalShortcut) -> Bool
    @ObservationIgnored private let wait: () async throws -> Void

    init(toasts: PasketToastCenter? = nil,
         systemAccess: SystemAccessController? = nil,
         hasAccess: @escaping () -> Bool = { CGPreflightPostEventAccess() },
         inputReleased: @escaping (UInt32?) -> Bool = ClipboardPasteController.inputIsReleased,
         clipboardChangeCount: @escaping () -> Int = { NSPasteboard.general.changeCount },
         postPaste: @escaping (pid_t, GlobalShortcut) -> Bool = ClipboardPasteController.postPasteEvent,
         wait: @escaping () async throws -> Void = { try await Task.sleep(for: .milliseconds(20)) }) {
        self.toasts = toasts ?? PasketToastCenter()
        self.systemAccess = systemAccess ?? SystemAccessController()
        self.hasAccess = hasAccess
        self.inputReleased = inputReleased
        self.clipboardChangeCount = clipboardChangeCount
        self.postPaste = postPaste
        self.wait = wait
    }

    func cancel() { requestID = UUID() }

    func prepareForPresentation() {
        cancel()
        errorMessage = nil
        needsPermission = false
        systemAccess.dismiss(.accessibility)
    }

    @discardableResult
    func paste(to target: Target?, using shortcut: GlobalShortcut = .defaultPaste,
               invocationKeyCode: UInt32? = nil, expectedChangeCount: Int? = nil, dismiss: () -> Void) async -> Bool {
        guard !Task.isCancelled else { return false }
        if let expectedChangeCount, clipboardChangeCount() != expectedChangeCount { return false }
        prepareForPresentation()
        guard let target, target.canPrepareForPaste else {
            errorMessage = "Item copied. Open history from the app where you want to paste, or use that app's Paste command."
            return false
        }
        guard hasAccess() else {
            needsPermission = true
            errorMessage = "Item copied. Allow Pasket in System Settings > Privacy & Security > Accessibility to paste automatically. You can also press Escape, then use the app's Paste command (\(shortcut.displayName))."
            systemAccess.present(.accessibility)
            return false
        }

        let changeCount = clipboardChangeCount()
        guard expectedChangeCount == nil || expectedChangeCount == changeCount else { return false }
        let request = UUID()
        requestID = request
        for _ in 0..<50 {
            do { try await wait() } catch { return false }
            guard !Task.isCancelled, requestID == request,
                  target.canPrepareForPaste,
                  clipboardChangeCount() == changeCount else { return false }
            guard inputReleased(invocationKeyCode) else { continue }
            guard hasAccess() else { return false }
            // Keep held Return repeats in the panel, then give AppKit time to release key focus.
            dismiss()
            requestID = request
            // A setup sheet can activate Pasket. Wait for dismissal to restore the original app.
            for _ in 0..<50 {
                do { try await wait() } catch { return false }
                guard !Task.isCancelled, requestID == request, target.canPrepareForPaste,
                      clipboardChangeCount() == changeCount, hasAccess() else { return false }
                if target.isActive() { return postPaste(target.processIdentifier, shortcut) }
            }
            return false
        }
        return false
    }

    func openAccessibilitySettings() {
        _ = CGRequestPostEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated private static func inputIsReleased(invocationKeyCode: UInt32?) -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
            return false
        }
        return !CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_Return))
            && !CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_ANSI_KeypadEnter))
            && (invocationKeyCode.map { !CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0)) } ?? true)
    }

    nonisolated private static func postPasteEvent(to processIdentifier: pid_t, shortcut: GlobalShortcut) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: false) else {
            return false
        }
        down.flags = shortcut.eventFlags
        up.flags = shortcut.eventFlags
        // Address the original process so a concurrent app switch cannot receive this paste.
        down.postToPid(processIdentifier)
        up.postToPid(processIdentifier)
        return true
    }
}
