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
    private(set) var isInitialized: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String

    var totalCount: Int { dailyCounts.values.reduce(0, +) }

    init(defaults: UserDefaults = .standard, storageKey: String = "historyPanelDailyOpenCounts") {
        self.defaults = defaults
        self.storageKey = storageKey
        isInitialized = defaults.dictionary(forKey: storageKey) != nil
        dailyCounts = (defaults.dictionary(forKey: storageKey) as? [String: Int] ?? [:])
            .filter { $0.value > 0 }
    }

    func initializeIfNeeded(with counts: [String: Int]) {
        guard !isInitialized else { return }
        dailyCounts = counts.filter { $0.value > 0 }
        save()
    }

    func recordEvent(at date: Date = .now, timeZone: TimeZone = .current) {
        let key = Self.dayKey(date, timeZone: timeZone)
        dailyCounts[key, default: 0] += 1
        save()
    }

    private func save() {
        // The dictionary itself is the initialization marker, including an empty baseline.
        defaults.set(dailyCounts, forKey: storageKey)
        isInitialized = true
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

    nonisolated static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        // Keep the local date of the event, even if the user later changes time zones.
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
}
