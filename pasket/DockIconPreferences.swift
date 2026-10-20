import Foundation
import Observation

enum DockIconColor: String, CaseIterable, Identifiable {
    case silver, orange, mint, blue, lavender, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .silver: "Space Silver"
        case .orange: "Orange"
        case .mint: "Mint"
        case .blue: "Blue"
        case .lavender: "Lavender"
        case .graphite: "Graphite"
        }
    }

    var assetName: String { "DockIcon" + rawValue.capitalized }
}

@MainActor @Observable
final class DockIconPreferences {
    private(set) var color: DockIconColor
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    private static let storageKey = "dockIconColor"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        color = defaults.string(forKey: Self.storageKey).flatMap(DockIconColor.init(rawValue:)) ?? .silver
    }

    func select(_ color: DockIconColor) {
        guard self.color != color else { return }
        self.color = color
        defaults.set(color.rawValue, forKey: Self.storageKey)
        onChange?()
    }
}
