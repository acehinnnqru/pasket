import Foundation
import OSLog

// Only identities and dates are needed to reserve the entire scrollable document.
nonisolated struct ClipboardHistoryReference: Identifiable, Equatable, Sendable {
    let id: UUID
    let copiedAt: Date
}

nonisolated struct ClipboardHistoryLayout {
    static let pageSize = 50
    static let rowHeight: Double = 50
    static let spacing: Double = 3
    static let inset: Double = 8
    static let firstHeaderHeight: Double = 24
    static let headerHeight: Double = 38

    struct Entry: Identifiable {
        enum ID: Hashable {
            case header(ClipboardHistoryPeriod)
            case item(UUID)
        }
        let id: ID
        let itemIndex: Int?
        let y: Double
        let height: Double
        var maxY: Double { y + height }
    }

    let entries: [Entry]
    let height: Double
    private let itemEntries: [UUID: Int]

    init(_ references: [ClipboardHistoryReference], at date: Date = .now,
         calendar: Calendar = .current, query: String = "") {
        self.init(references, at: date, calendar: calendar,
                  isSearch: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    init(_ references: [ClipboardHistoryReference], at date: Date,
         calendar: Calendar = .current, isSearch: Bool) {
        let signposter = HistoryPerformance.signposter
        let mode = isSearch ? "search" : "date"
        let interval = signposter.beginInterval("History Layout Build", id: signposter.makeSignpostID(),
                                                "references=\(references.count) mode=\(mode, privacy: .public)")
        defer { signposter.endInterval("History Layout Build", interval) }

        var entries: [Entry] = []
        var itemEntries: [UUID: Int] = [:]
        var y = Self.inset
        var previousPeriod: ClipboardHistoryPeriod?
        for (index, reference) in references.enumerated() {
            let period: ClipboardHistoryPeriod = isSearch ? .searchResults
                : .period(for: reference.copiedAt, at: date, calendar: calendar)
            if period != previousPeriod {
                let height = previousPeriod == nil ? Self.firstHeaderHeight : Self.headerHeight
                entries.append(Entry(id: .header(period), itemIndex: nil, y: y, height: height))
                y += height + Self.spacing
                previousPeriod = period
            }
            itemEntries[reference.id] = entries.count
            entries.append(Entry(id: .item(reference.id), itemIndex: index, y: y, height: Self.rowHeight))
            y += Self.rowHeight + Self.spacing
        }
        self.entries = entries
        self.itemEntries = itemEntries
        height = y - (entries.isEmpty ? 0 : Self.spacing) + Self.inset
    }

    struct Cache {
        private enum Grouping: Equatable {
            case search
            case date(day: Date, calendar: Calendar)
        }

        private var cached: (revision: UUID, grouping: Grouping, layout: ClipboardHistoryLayout)?

        // The revision identifies the ordered references, independently of row summaries.
        mutating func layout(for references: [ClipboardHistoryReference], revision: UUID, at date: Date,
                             calendar: Calendar = .current, isSearch: Bool) -> ClipboardHistoryLayout {
            let grouping: Grouping = isSearch ? .search : .date(day: calendar.startOfDay(for: date), calendar: calendar)
            if let cached, cached.revision == revision, cached.grouping == grouping { return cached.layout }

            let layout = ClipboardHistoryLayout(references, at: date, calendar: calendar, isSearch: isSearch)
            cached = (revision, grouping, layout)
            return layout
        }
    }

    // Binary search avoids walking every reserved row during scrollbar drags.
    func visibleEntries(in viewport: Range<Double>, overscan: Double = 200) -> Range<Int> {
        func lowerBound(_ predicate: (Entry) -> Bool) -> Int {
            var low = 0
            var high = entries.count
            while low < high {
                let middle = (low + high) / 2
                if predicate(entries[middle]) { high = middle } else { low = middle + 1 }
            }
            return low
        }
        let start = lowerBound { $0.maxY > viewport.lowerBound - overscan }
        let end = lowerBound { $0.y >= viewport.upperBound + overscan }
        return start..<max(start, end)
    }

    func itemRange(in entryRange: Range<Int>) -> Range<Int> {
        let indices = entries[entryRange].compactMap(\.itemIndex)
        guard let first = indices.first, let last = indices.last else { return 0..<0 }
        return first..<(last + 1)
    }

    func entry(for id: UUID) -> Entry? { itemEntries[id].map { entries[$0] } }

    func scrollOffset(revealing id: UUID, in viewport: Range<Double>) -> Double? {
        guard let entry = entry(for: id) else { return nil }
        if entry.y < viewport.lowerBound { return entry.y }
        if entry.maxY > viewport.upperBound { return max(0, entry.maxY - (viewport.upperBound - viewport.lowerBound)) }
        return nil
    }
}
