import Foundation

nonisolated enum ClipboardTextSeparator: String, CaseIterable, Identifiable {
    case newline, space, blankLine, none
    var id: Self { self }
    var title: String {
        switch self {
        case .newline: "New Line"
        case .space: "Space"
        case .blankLine: "Blank Line"
        case .none: "None"
        }
    }
    var value: String {
        switch self {
        case .newline: "\n"
        case .space: " "
        case .blankLine: "\n\n"
        case .none: ""
        }
    }
}

nonisolated enum ClipboardBatch {
    static func canCombine(_ items: [ClipboardItem]) -> Bool {
        !items.isEmpty && (items.allSatisfy { [.text, .link, .email].contains($0.kind) }
            || items.allSatisfy { $0.kind == .file })
    }

    static let unsupportedMessage = "Paste Together supports text, links, and emails together, or a group of files. Use a paste queue for images or mixed content."
}
