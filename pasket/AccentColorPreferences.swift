import Observation
import SwiftUI

enum AccentColorOption: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .graphite: "Graphite"
        }
    }

    // A nil override preserves the system accent, including future system changes.
    var tint: Color? {
        switch self {
        case .system: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .graphite: .gray
        }
    }
}

@MainActor @Observable
final class AccentColorPreferences {
    private(set) var color: AccentColorOption
    @ObservationIgnored private let defaults: UserDefaults

    private static let storageKey = "accentColor"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        color = defaults.string(forKey: Self.storageKey).flatMap(AccentColorOption.init(rawValue:)) ?? .system
    }

    func select(_ color: AccentColorOption) {
        guard self.color != color else { return }
        defaults.set(color.rawValue, forKey: Self.storageKey)
        self.color = color
    }
}

struct PasketAccentColor: ViewModifier {
    var preferences: AccentColorPreferences

    func body(content: Content) -> some View {
        content
            .accentColor(preferences.color.tint)
            .tint(preferences.color.tint)
    }
}
