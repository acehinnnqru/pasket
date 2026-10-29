import Observation
import SwiftUI

enum AppearanceOption: String, CaseIterable, Identifiable {
    case liquidGlass, classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .classic: "Classic"
        }
    }

    var explanation: String {
        switch self {
        case .liquidGlass: "Liquid Glass follows your system appearance and transparency preferences."
        case .classic: "Classic keeps Pasket's frosted surfaces."
        }
    }
}

@MainActor @Observable
final class AppearancePreferences {
    private(set) var appearance: AppearanceOption
    @ObservationIgnored private let defaults: UserDefaults

    private static let storageKey = "appearance"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Self.storageKey).flatMap(AppearanceOption.init(rawValue:)) ?? .liquidGlass
    }

    func select(_ appearance: AppearanceOption) {
        guard self.appearance != appearance else { return }
        defaults.set(appearance.rawValue, forKey: Self.storageKey)
        self.appearance = appearance
    }
}

extension EnvironmentValues {
    @Entry var pasketAppearance: AppearanceOption = .liquidGlass
}

struct PasketAppearance: ViewModifier {
    var preferences: AppearancePreferences

    func body(content: Content) -> some View {
        content.environment(\.pasketAppearance, preferences.appearance)
    }
}
