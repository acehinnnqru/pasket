import Foundation
import Testing
@testable import PasketCore

@MainActor
struct HistoryStatisticsTests {
    @Test func copyBaselineIsOneTimeEvenWhenEmptyAndIndependentOfOpens() throws {
        let suite = "HistoryStatisticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let copies = HistoryStatistics(defaults: defaults, storageKey: "clipboardDailyCopyCounts")
        let opens = HistoryStatistics(defaults: defaults)
        #expect(!copies.isInitialized)
        copies.initializeIfNeeded(with: [:])
        let restored = HistoryStatistics(defaults: defaults, storageKey: "clipboardDailyCopyCounts")
        #expect(restored.isInitialized)
        restored.initializeIfNeeded(with: ["2026-10-27": 10])
        #expect(restored.totalCount == 0)
        restored.recordEvent()
        restored.recordEvent()
        opens.recordEvent()
        #expect(restored.totalCount == 2)
        #expect(opens.totalCount == 1)
    }

    @Test func countsAccumulateAndSurviveRelaunch() throws {
        let suite = "HistoryStatisticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let statistics = HistoryStatistics(defaults: defaults)
        let zone = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-27T05:00:00Z"))

        #expect(statistics.days(endingAt: date, count: 7, timeZone: zone).map(\.count) == Array(repeating: 0, count: 7))
        #expect(statistics.totalCount == 0)
        statistics.recordEvent(at: date.addingTimeInterval(-120 * 86400), timeZone: zone)
        statistics.recordEvent(at: date, timeZone: zone)
        statistics.recordEvent(at: date.addingTimeInterval(60), timeZone: zone)
        #expect(statistics.totalCount == 3)

        let restored = HistoryStatistics(defaults: defaults)
        #expect(restored.totalCount == 3)
        #expect(restored.days(endingAt: date, count: 3, timeZone: zone).map(\.count) == [0, 0, 2])
        #expect(restored.days(endingAt: date, count: 0, timeZone: zone).isEmpty)
    }

    @Test func localMidnightSplitsDaysAndPreservesGaps() throws {
        let suite = "HistoryStatisticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let statistics = HistoryStatistics(defaults: defaults)
        let zone = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        let midnight = try #require(ISO8601DateFormatter().date(from: "2026-12-31T16:00:00Z"))

        statistics.recordEvent(at: midnight.addingTimeInterval(-1), timeZone: zone)
        statistics.recordEvent(at: midnight, timeZone: zone)
        statistics.recordEvent(at: midnight.addingTimeInterval(2 * 86400), timeZone: zone)

        let days = statistics.days(endingAt: midnight.addingTimeInterval(2 * 86400), count: 4, timeZone: zone)
        #expect(days.map(\.count) == [1, 1, 0, 1])
        #expect(Set(days.map(\.id)).count == 4)
    }

    @Test func daylightSavingUsesCalendarDays() throws {
        let suite = "HistoryStatisticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let statistics = HistoryStatistics(defaults: defaults)
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        let beforeJump = try #require(formatter.date(from: "2026-03-08T09:59:59Z"))
        let afterJump = try #require(formatter.date(from: "2026-03-08T10:00:00Z"))
        let nextDay = try #require(formatter.date(from: "2026-03-09T07:00:00Z"))
        statistics.recordEvent(at: beforeJump, timeZone: zone)
        statistics.recordEvent(at: afterJump, timeZone: zone)
        statistics.recordEvent(at: nextDay, timeZone: zone)

        let days = statistics.days(endingAt: nextDay, count: 3, timeZone: zone)
        #expect(days.map(\.count) == [0, 2, 1])
        #expect(days[2].date.timeIntervalSince(days[1].date) == 23 * 3600)
    }

    @Test func changingTimeZonesKeepsRecordedLocalDates() throws {
        let suite = "HistoryStatisticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let statistics = HistoryStatistics(defaults: defaults)
        let shanghai = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-27T01:00:00Z"))
        statistics.recordEvent(at: date, timeZone: shanghai)
        statistics.recordEvent(at: date, timeZone: losAngeles)

        #expect(statistics.days(endingAt: date, count: 2, timeZone: shanghai).map(\.count) == [1, 1])
    }
}
