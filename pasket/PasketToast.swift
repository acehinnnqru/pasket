import Foundation
import Observation

struct PasketToast: Identifiable, Equatable {
    enum Source { case notice, copy, paste, storage, retention, pasteOrderHint }
    enum Style { case success, information, warning, error }
    enum Action {
        case retryStorage, reviewHistory

        var title: String {
            switch self {
            case .retryStorage: "Retry"
            case .reviewHistory: "Review Settings…"
            }
        }
    }

    let id = UUID()
    let source: Source
    let title: String
    let message: String
    let style: Style
    var action: Action?

    // Actionable problems stay available until dismissed or resolved.
    var duration: Duration? {
        if action != nil { return nil }
        return style == .success || source == .pasteOrderHint ? .seconds(4) : .seconds(8)
    }
}

@MainActor @Observable
final class PasketToastCenter {
    private(set) var messages: [PasketToast] = []
    var current: PasketToast? { messages.last }

    func show(_ message: String?, source: PasketToast.Source, title: String,
              style: PasketToast.Style, action: PasketToast.Action? = nil) {
        dismiss(source: source)
        guard let message else { return }
        messages.append(PasketToast(source: source, title: title, message: message,
                                    style: style, action: action))
    }

    func dismiss(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    func dismiss(source: PasketToast.Source) {
        messages.removeAll { $0.source == source }
    }

    func dismissTransient() {
        messages.removeAll { $0.action == nil }
    }

    func dismissAll() { messages.removeAll() }
}
