import Foundation
import Testing
@testable import PasketCore

@Suite @MainActor
struct DockIconPreferencesTests {
    @Test func dockVisibilityDefaultsToHidden() throws {
        let suite = "PasketDockIconTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!DockIconPreferences(defaults: defaults).showInDock)
    }

    @Test func dockVisibilityIsSavedBeforeDeliveryAndIndependentOfColor() throws {
        let suite = "PasketDockIconTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = DockIconPreferences(defaults: defaults)
        preferences.select(.mint)
        var delivered: [Bool] = []
        preferences.onChange = {
            delivered.append(DockIconPreferences(defaults: defaults).showInDock)
        }

        preferences.setShowInDock(true)
        #expect(preferences.showInDock)
        #expect(delivered == [true])
        #expect(DockIconPreferences(defaults: defaults).showInDock)
        preferences.setShowInDock(true)
        #expect(delivered == [true])

        preferences.select(.orange)
        #expect(preferences.showInDock)
        #expect(DockIconPreferences(defaults: defaults).showInDock)
        preferences.setShowInDock(false)
        #expect(!preferences.showInDock)
        #expect(delivered == [true, true, false])
        #expect(!DockIconPreferences(defaults: defaults).showInDock)
        #expect(DockIconPreferences(defaults: defaults).color == .orange)
    }

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
