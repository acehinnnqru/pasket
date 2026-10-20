import Foundation
import Testing
@testable import PasketCore

@Suite @MainActor
struct AccentColorPreferencesTests {
    @Test func newAndUnrecognizedPreferencesFollowSystem() throws {
        let suite = "PasketAccentColorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AccentColorPreferences(defaults: defaults).color == .system)
        #expect(AccentColorOption.system.tint == nil)
        defaults.set("removed-color", forKey: "accentColor")
        #expect(AccentColorPreferences(defaults: defaults).color == .system)
    }

    @Test func selectionsSurviveRelaunchIndependentlyOfDockIcon() throws {
        let suite = "PasketAccentColorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = AccentColorPreferences(defaults: defaults)
        let dockIcon = DockIconPreferences(defaults: defaults)
        dockIcon.select(.mint)
        for color in AccentColorOption.allCases.reversed() {
            preferences.select(color)
            #expect(preferences.color == color)
            #expect(AccentColorPreferences(defaults: defaults).color == color)
            #expect(DockIconPreferences(defaults: defaults).color == .mint)
        }
        #expect(preferences.color == .system)
    }
}
