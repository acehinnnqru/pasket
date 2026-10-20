import Foundation
import Observation

@MainActor @Observable
final class SystemAccessController {
    enum Permission { case accessibility, clipboard }

    struct Request: Identifiable {
        let id = UUID()
        let permission: Permission

        var title: String {
            switch permission {
            case .accessibility: "Allow Automatic Paste?"
            case .clipboard: "Allow Clipboard Collection?"
            }
        }

        var message: String {
            switch permission {
            case .accessibility:
                "Your item has been copied. Allow Pasket in System Settings > Privacy & Security > Accessibility to paste automatically.\n\nAlready allowed access? Quit and reopen Pasket to refresh its permissions, then try pasting again.\n\nTo paste manually, cancel, press Escape, and use Command + V in your app."
            case .clipboard:
                "Allow Pasket to read the clipboard in System Settings to collect new items. Your saved history is still available. After allowing access, copy the item again."
            }
        }
    }

    private(set) var request: Request?

    func present(_ permission: Permission) {
        request = Request(permission: permission)
    }

    func dismiss(_ permission: Permission? = nil) {
        if permission == nil || request?.permission == permission { request = nil }
    }
}
