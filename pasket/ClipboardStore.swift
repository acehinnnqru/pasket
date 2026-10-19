import AppKit
import Observation

enum ClipboardKind: String, CaseIterable, Identifiable {
    case text, image, file, link, email

    var id: Self { self }
    var title: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        case .file: "File"
        case .link: "Link"
        case .email: "Email"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        case .link: "link"
        case .email: "at"
        }
    }
}

enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all, text, images, files, links, emails

    var id: Self { self }
    var kind: ClipboardKind? {
        switch self {
        case .all: nil
        case .text: .text
        case .images: .image
        case .files: .file
        case .links: .link
        case .emails: .email
        }
    }

    var title: String {
        switch self {
        case .all: "All Types"
        case .text: "Text Only"
        case .images: "Images Only"
        case .files: "Files Only"
        case .links: "Links Only"
        case .emails: "Emails Only"
        }
    }

    var symbol: String { kind?.symbol ?? "list.bullet" }
}

struct ClipboardItem: Identifiable {
    let id = UUID()
    let kind: ClipboardKind
    let title: String
    let content: String
    let source: String
    let copiedAt: Date
    var isCode = false

    var canCopy: Bool { kind != .image && kind != .file }

    static var samples: [ClipboardItem] {
        let now = Date()
        return [
            ClipboardItem(kind: .link, title: "https://example.com/design/pasket", content: "https://example.com/design/pasket", source: "Safari", copiedAt: now),
            ClipboardItem(kind: .text, title: "A little basket for everything you copy.", content: "A little basket for everything you copy.\n\nFind a thought, a link, or a file — right when you need it.", source: "Notes", copiedAt: now.addingTimeInterval(-120)),
            ClipboardItem(kind: .image, title: "Image · 1440 × 900", content: "Sample image", source: "Screenshot", copiedAt: now.addingTimeInterval(-300)),
            ClipboardItem(kind: .file, title: "Product brief.pdf", content: "~/Documents/Product brief.pdf", source: "Finder", copiedAt: now.addingTimeInterval(-480)),
            ClipboardItem(kind: .email, title: "hello@example.com", content: "hello@example.com", source: "Mail", copiedAt: now.addingTimeInterval(-720)),
            ClipboardItem(kind: .text, title: "let basket = ClipboardHistory()", content: "let basket = ClipboardHistory()\nbasket.startCollecting()", source: "Xcode", copiedAt: now.addingTimeInterval(-900), isCode: true)
        ]
    }
}

@MainActor @Observable
final class ClipboardStore {
    var query = ""
    var filter: ClipboardFilter = .all
    var selectedID: ClipboardItem.ID?
    var presentationID = UUID()
    private(set) var copyError: String?
    private(set) var items: [ClipboardItem]

    init(items: [ClipboardItem]? = nil) {
        let initialItems = items ?? ClipboardItem.samples
        self.items = initialItems
        selectedID = initialItems.first?.id
    }

    var filteredItems: [ClipboardItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            (filter.kind == nil || filter.kind == item.kind)
                && (search.isEmpty || [item.title, item.content, item.source].contains {
                    $0.localizedStandardContains(search)
                })
        }
    }

    var selectedItem: ClipboardItem? {
        filteredItems.first { $0.id == selectedID }
    }

    func prepareForPresentation() {
        query = ""
        filter = .all
        selectedID = items.first?.id
        copyError = nil
        presentationID = UUID()
    }

    func reconcileSelection() {
        copyError = nil
        if !filteredItems.contains(where: { $0.id == selectedID }) {
            selectedID = filteredItems.first?.id
        }
    }

    func moveSelection(by offset: Int) {
        let visibleItems = filteredItems
        guard !visibleItems.isEmpty else { return }
        let current = visibleItems.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : visibleItems.count)
        let next = min(max(current + offset, 0), visibleItems.count - 1)
        selectedID = visibleItems[next].id
        copyError = nil
    }

    @discardableResult
    func copySelection() -> Bool {
        guard let item = selectedItem, item.canCopy else { return false }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(item.content, forType: .string) else {
            copyError = "Could not copy this item. Try again."
            return false
        }
        copyError = nil
        return true
    }
}
