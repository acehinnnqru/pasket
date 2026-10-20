import AppKit
import Carbon.HIToolbox
import Observation

@MainActor @Observable
final class ClipboardPasteController {
    struct Target {
        let processIdentifier: pid_t
        let isActive: () -> Bool
        let isTerminated: () -> Bool

        init(application: NSRunningApplication) {
            processIdentifier = application.processIdentifier
            isActive = { application.isActive }
            isTerminated = { application.isTerminated }
        }

        init(processIdentifier: pid_t, isActive: @escaping () -> Bool,
             isTerminated: @escaping () -> Bool) {
            self.processIdentifier = processIdentifier
            self.isActive = isActive
            self.isTerminated = isTerminated
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
    @ObservationIgnored private let inputReleased: () -> Bool
    @ObservationIgnored private let clipboardChangeCount: () -> Int
    @ObservationIgnored private let postPaste: (pid_t) -> Bool
    @ObservationIgnored private let wait: () async throws -> Void

    init(toasts: PasketToastCenter? = nil,
         systemAccess: SystemAccessController? = nil,
         hasAccess: @escaping () -> Bool = { CGPreflightPostEventAccess() },
         inputReleased: @escaping () -> Bool = ClipboardPasteController.inputIsReleased,
         clipboardChangeCount: @escaping () -> Int = { NSPasteboard.general.changeCount },
         postPaste: @escaping (pid_t) -> Bool = ClipboardPasteController.postPasteEvent,
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
    func paste(to target: Target?, dismiss: () -> Void) async -> Bool {
        guard !Task.isCancelled else { return false }
        prepareForPresentation()
        guard let target, !target.isTerminated(), target.isActive() else {
            errorMessage = "Item copied. Open history from the app where you want to paste, or press Command + V there."
            return false
        }
        guard hasAccess() else {
            needsPermission = true
            errorMessage = "Item copied. Allow Pasket in System Settings > Privacy & Security > Accessibility to paste automatically. You can also press Escape, then Command + V."
            systemAccess.present(.accessibility)
            return false
        }

        let changeCount = clipboardChangeCount()
        let request = UUID()
        requestID = request
        for _ in 0..<50 {
            do { try await wait() } catch { return false }
            guard !Task.isCancelled, requestID == request,
                  !target.isTerminated(), target.isActive(),
                  clipboardChangeCount() == changeCount else { return false }
            guard inputReleased() else { continue }
            guard hasAccess() else { return false }
            // Keep held Return repeats in the panel, then give AppKit time to release key focus.
            dismiss()
            requestID = request
            do { try await wait() } catch { return false }
            guard !Task.isCancelled, requestID == request,
                  !target.isTerminated(), target.isActive(),
                  clipboardChangeCount() == changeCount, hasAccess() else { return false }
            return postPaste(target.processIdentifier)
        }
        return false
    }

    func openAccessibilitySettings() {
        _ = CGRequestPostEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated private static func inputIsReleased() -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
            return false
        }
        return !CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_Return))
            && !CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_ANSI_KeypadEnter))
    }

    nonisolated private static func postPasteEvent(to processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        // Address the original process so a concurrent app switch cannot receive this paste.
        down.postToPid(processIdentifier)
        up.postToPid(processIdentifier)
        return true
    }
}
