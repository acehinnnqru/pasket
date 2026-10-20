import Foundation
import Testing
@testable import PasketCore

@Suite @MainActor
struct DockIconPreferencesTests {
    @Test func newAndUnrecognizedPreferencesUseSpaceSilver() throws {
        let suite = "PasketDockIconTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(DockIconPreferences(defaults: defaults).color == .silver)
        defaults.set("removed-color", forKey: "dockIconColor")
        #expect(DockIconPreferences(defaults: defaults).color == .silver)
    }

    @Test func selectionsAreSavedBeforeDeliveryAndRestoredOnRelaunch() throws {
        let suite = "PasketDockIconTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = DockIconPreferences(defaults: defaults)
        var delivered: [DockIconColor] = []
        preferences.onChange = {
            delivered.append(DockIconPreferences(defaults: defaults).color)
        }
        for color in [DockIconColor.orange, .mint, .blue, .lavender, .graphite, .silver] {
            preferences.select(color)
            #expect(preferences.color == color)
            #expect(delivered.last == color)
            #expect(DockIconPreferences(defaults: defaults).color == color)
        }
        let count = delivered.count
        preferences.select(.silver)
        #expect(delivered.count == count)
    }
}
