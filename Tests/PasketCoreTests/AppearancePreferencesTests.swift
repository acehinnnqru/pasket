import Foundation
import Testing
@testable import PasketCore

@Suite @MainActor
struct AppearancePreferencesTests {
    @Test func newAndUnrecognizedPreferencesUseLiquidGlass() throws {
        let suite = "PasketAppearanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppearancePreferences(defaults: defaults).appearance == .liquidGlass)
        defaults.set("removed-appearance", forKey: "appearance")
        #expect(AppearancePreferences(defaults: defaults).appearance == .liquidGlass)
    }

    @Test func selectionsSurviveRelaunchIndependentlyOfAccentAndDockIcon() throws {
        let suite = "PasketAppearanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = AppearancePreferences(defaults: defaults)
        let accentColor = AccentColorPreferences(defaults: defaults)
        let dockIcon = DockIconPreferences(defaults: defaults)
        accentColor.select(.purple)
        dockIcon.select(.mint)

        for appearance in AppearanceOption.allCases.reversed() {
            preferences.select(appearance)
            #expect(preferences.appearance == appearance)
            #expect(AppearancePreferences(defaults: defaults).appearance == appearance)
            #expect(AccentColorPreferences(defaults: defaults).color == .purple)
            #expect(DockIconPreferences(defaults: defaults).color == .mint)
        }

        accentColor.select(.system)
        dockIcon.select(.blue)
        #expect(AppearancePreferences(defaults: defaults).appearance == .liquidGlass)
    }
}
