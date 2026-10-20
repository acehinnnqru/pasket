import Foundation
import Testing
@testable import PasketCore

@Suite @MainActor
struct ClipboardFilterPreferencesTests {
    @Test func defaultAndUnknownPreferencesUseOneMinute() throws {
        let suite = "PasketFilterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ClipboardFilterPreferences(defaults: defaults).memory == .oneMinute)
        defaults.set("removed-option", forKey: "clipboardFilterMemory")
        #expect(ClipboardFilterPreferences(defaults: defaults).memory == .oneMinute)
    }

    @Test(arguments: ClipboardFilterMemory.allCases)
    func preferenceSurvivesRelaunch(memory: ClipboardFilterMemory) throws {
        let suite = "PasketFilterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = ClipboardFilterPreferences(defaults: defaults)
        preferences.select(memory)
        #expect(ClipboardFilterPreferences(defaults: defaults).memory == memory)
    }

    @Test(arguments: [
        (ClipboardFilterMemory.never, 0.0, false),
        (.thirtySeconds, 29.999, true), (.thirtySeconds, 30, false),
        (.oneMinute, 59.999, true), (.oneMinute, 60, false),
        (.fiveMinutes, 299.999, true), (.fiveMinutes, 300, false),
        (.untilQuit, 86_400, true)
    ])
    func expirationUsesTheChosenInterval(memory: ClipboardFilterMemory, elapsed: TimeInterval, retained: Bool) {
        let closedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(memory.retainsFilter(closedAt: closedAt, reopeningAt: closedAt.addingTimeInterval(elapsed)) == retained)
        #expect(!memory.retainsFilter(closedAt: nil, reopeningAt: closedAt))
        #expect(!memory.retainsFilter(closedAt: closedAt, reopeningAt: closedAt.addingTimeInterval(-1)))
    }
}
