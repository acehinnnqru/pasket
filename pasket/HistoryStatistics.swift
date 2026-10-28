import Foundation
import Observation

struct HistoryStatisticsDay: Identifiable {
    let date: Date
    let count: Int

    var id: Date { date }
}

@MainActor @Observable
final class HistoryStatistics {
    private(set) var dailyCounts: [String: Int]
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "historyPanelDailyOpenCounts"

    var totalCount: Int { dailyCounts.values.reduce(0, +) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dailyCounts = (defaults.dictionary(forKey: Self.storageKey) as? [String: Int] ?? [:])
            .filter { $0.value > 0 }
    }

    func recordOpen(at date: Date = .now, timeZone: TimeZone = .current) {
        let key = Self.dayKey(date, timeZone: timeZone)
        dailyCounts[key, default: 0] += 1
        defaults.set(dailyCounts, forKey: Self.storageKey)
    }

    func days(endingAt date: Date = .now, count: Int, timeZone: TimeZone = .current) -> [HistoryStatisticsDay] {
        guard count > 0 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return HistoryStatisticsDay(date: day, count: dailyCounts[Self.dayKey(day, timeZone: timeZone)] ?? 0)
        }
    }

    private static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        // Keep the local date at the time of opening, even if the user later changes time zones.
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
}
