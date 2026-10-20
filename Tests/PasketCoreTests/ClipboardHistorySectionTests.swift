import Foundation
import Testing
@testable import PasketCore

struct ClipboardHistorySectionTests {
    private func calendar(in timeZone: String = "Asia/Shanghai") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    @Test func groupsCalendarBoundariesWithoutDroppingOrReorderingItems() throws {
        let calendar = calendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12)))
        let ages = [0, 0, 1, 2, 7, 8, 30, 31, 365]
        let items = try ages.enumerated().map { index, age in
            let date = try #require(calendar.date(byAdding: .day, value: -age, to: now))
            return ClipboardItem.text("Entry \(index)", source: .unknown, at: date)
        }
        let sections = ClipboardHistorySection.grouping(items, at: now, calendar: calendar)

        #expect(sections.map(\.period) == [.today, .yesterday, .sevenDays, .thirtyDays, .older])
        #expect(sections.map { $0.items.count } == [2, 1, 2, 2, 2])
        #expect(sections.flatMap(\.items).map(\.id) == items.map(\.id))
        #expect(ClipboardHistorySection.grouping([], at: now, calendar: calendar).isEmpty)
        let filtered = ClipboardHistorySection.grouping([items[3], items[4]], at: now, calendar: calendar)
        #expect(filtered.map(\.period) == [.sevenDays])
        #expect(filtered.flatMap(\.items).map(\.id) == [items[3].id, items[4].id])
    }

    @Test func midnightUsesTheLocalCalendarAndRegroupsOnTheNextDay() throws {
        let calendar = calendar()
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
        let items = [
            ClipboardItem.text("At midnight", source: .unknown, at: midnight),
            ClipboardItem.text("Before midnight", source: .unknown, at: midnight.addingTimeInterval(-1))
        ]
        let sections = ClipboardHistorySection.grouping(items, at: midnight, calendar: calendar)
        #expect(sections.map(\.period) == [.today, .yesterday])

        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))
        let regrouped = ClipboardHistorySection.grouping(items, at: tomorrow, calendar: calendar)
        #expect(regrouped.map(\.period) == [.yesterday, .sevenDays])

        let utcSections = ClipboardHistorySection.grouping(items, at: midnight, calendar: self.calendar(in: "UTC"))
        #expect(utcSections.map(\.period) == [.today])
    }

    @Test func daylightSavingUsesCalendarDaysInsteadOfElapsedHours() throws {
        let calendar = calendar(in: "America/Los_Angeles")
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 30)))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        #expect(now.timeIntervalSince(yesterday) > 24 * 60 * 60)
        let item = ClipboardItem.text("Before the clock change", source: .unknown, at: yesterday)
        let sections = ClipboardHistorySection.grouping([item], at: now, calendar: calendar)
        #expect(sections.map(\.period) == [.yesterday])
    }
}
