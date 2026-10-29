import Foundation
import Testing
@testable import PasketCore

struct ClipboardHistoryLayoutTests {
    @Test func fullDocumentGeometryIncludesUnloadedRowsAndDateHeaders() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12)))
        let ages = [0, 0, 1, 4, 20, 40]
        let references = try ages.map { age in
            ClipboardHistoryReference(id: UUID(), copiedAt: try #require(calendar.date(byAdding: .day, value: -age, to: now)))
        }
        let layout = ClipboardHistoryLayout(references, at: now, calendar: calendar)
        let headers = layout.entries.compactMap { entry -> ClipboardHistoryPeriod? in
            if case .header(let period) = entry.id { return period }
            return nil
        }
        #expect(headers == [.today, .yesterday, .sevenDays, .thirtyDays, .older])
        // Two insets, five headers, six rows, and ten inter-entry gaps.
        #expect(layout.height == 522)
        #expect(layout.entries.compactMap(\.itemIndex) == Array(references.indices))
        #expect(Set(layout.entries.map(\.id)).count == layout.entries.count)
        for (first, second) in zip(layout.entries, layout.entries.dropFirst()) {
            #expect(second.y - first.maxY == ClipboardHistoryLayout.spacing)
        }
        let search = ClipboardHistoryLayout(references.reversed(), at: now, query: "match")
        #expect(search.entries.first?.id == .header(.searchResults))
        #expect(search.entries.filter { $0.itemIndex == nil }.count == 1)
    }

    @Test func draggingNearTheEndCreatesOnlyNearbyRows() throws {
        let references = (0..<10_000).map { _ in ClipboardHistoryReference(id: UUID(), copiedAt: .now) }
        let layout = ClipboardHistoryLayout(references, query: "match")
        let target = try #require(layout.entry(for: references[9_950].id))
        let visible = layout.visibleEntries(in: target.y..<(target.y + 500))
        let range = layout.itemRange(in: visible)
        #expect(range.contains(9_950))
        #expect(range.lowerBound > 9_900)
        #expect(visible.count < 25)
        let bottom = layout.visibleEntries(in: (layout.height - 500)..<layout.height)
        #expect(layout.itemRange(in: bottom).upperBound == 10_000)
        #expect(layout.visibleEntries(in: (-1000)..<(-900), overscan: 0).isEmpty)
        #expect(layout.visibleEntries(in: (layout.height + 1)..<(layout.height + 100), overscan: 0).isEmpty)
        #expect(ClipboardHistoryLayout([]).itemRange(in: 0..<0).isEmpty)
    }

    @Test func keyboardRevealsTargetsWithoutMovingAnAlreadyVisibleRow() throws {
        let references = (0..<100).map { _ in ClipboardHistoryReference(id: UUID(), copiedAt: .now) }
        let layout = ClipboardHistoryLayout(references)
        let entry = try #require(layout.entry(for: references[70].id))
        #expect(layout.scrollOffset(revealing: references[70].id, in: 0..<500) == entry.maxY - 500)
        #expect(layout.scrollOffset(revealing: references[70].id, in: entry.y..<(entry.y + 500)) == nil)
        #expect(layout.scrollOffset(revealing: references[0].id, in: entry.y..<(entry.y + 500))
            == layout.entry(for: references[0].id)?.y)
    }
}
